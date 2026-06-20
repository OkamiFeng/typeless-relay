import Darwin
import Dispatch
import Foundation

enum RelayError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case socket(String)
    case socks(String)
    case unexpectedEOF

    var description: String {
        switch self {
        case .invalidArgument(let message), .socket(let message), .socks(let message):
            return message
        case .unexpectedEOF:
            return "unexpected end of stream"
        }
    }
}

struct Configuration {
    let listenHost: String
    let listenPort: UInt16
    let socksHost: String
    let socksPort: UInt16
    let targetHost: String
    let targetPort: UInt16

    static func parse(_ arguments: [String]) throws -> Configuration {
        var values: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw RelayError.invalidArgument("invalid argument: \(key)")
            }
            values[key] = arguments[index + 1]
            index += 2
        }

        func required(_ key: String) throws -> String {
            guard let value = values[key], !value.isEmpty else {
                throw RelayError.invalidArgument("missing argument: \(key)")
            }
            return value
        }

        func port(_ key: String) throws -> UInt16 {
            let value = try required(key)
            guard let parsed = UInt16(value), parsed > 0 else {
                throw RelayError.invalidArgument("invalid port for \(key): \(value)")
            }
            return parsed
        }

        return Configuration(
            listenHost: try required("--listen-host"),
            listenPort: try port("--listen-port"),
            socksHost: try required("--socks-host"),
            socksPort: try port("--socks-port"),
            targetHost: try required("--target-host"),
            targetPort: try port("--target-port")
        )
    }
}

func errorMessage(_ operation: String) -> String {
    "\(operation): \(String(cString: strerror(errno)))"
}

func configureSocket(_ socket: Int32) {
    var enabled: Int32 = 1
    setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
}

func ipv4Address(host: String, port: UInt16) throws -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
        throw RelayError.invalidArgument("only IPv4 literals are supported for local endpoints: \(host)")
    }
    return address
}

func withSocketAddress<T>(
    _ address: inout sockaddr_in,
    _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
) rethrows -> T {
    try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            try body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
}

func openTCP(host: String, port: UInt16, listener: Bool) throws -> Int32 {
    let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard socket >= 0 else { throw RelayError.socket(errorMessage("socket")) }
    configureSocket(socket)

    do {
        var address = try ipv4Address(host: host, port: port)
        if listener {
            var reuseAddress: Int32 = 1
            setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, socklen_t(MemoryLayout<Int32>.size))
            let result = withSocketAddress(&address) { Darwin.bind(socket, $0, $1) }
            guard result == 0 else { throw RelayError.socket(errorMessage("bind")) }
            guard Darwin.listen(socket, 128) == 0 else { throw RelayError.socket(errorMessage("listen")) }
        } else {
            let result = withSocketAddress(&address) { Darwin.connect(socket, $0, $1) }
            guard result == 0 else { throw RelayError.socket(errorMessage("connect")) }
        }
        return socket
    } catch {
        Darwin.close(socket)
        throw error
    }
}

func readExact(_ socket: Int32, count: Int) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: count)
    var offset = 0
    while offset < count {
        let received = bytes.withUnsafeMutableBytes { buffer -> Int in
            Darwin.recv(socket, buffer.baseAddress!.advanced(by: offset), count - offset, 0)
        }
        if received == 0 { throw RelayError.unexpectedEOF }
        if received < 0 {
            if errno == EINTR { continue }
            throw RelayError.socket(errorMessage("recv"))
        }
        offset += received
    }
    return bytes
}

func writeAll(_ socket: Int32, bytes: [UInt8]) throws {
    var offset = 0
    while offset < bytes.count {
        let sent = bytes.withUnsafeBytes { buffer -> Int in
            Darwin.send(socket, buffer.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
        }
        if sent < 0 {
            if errno == EINTR { continue }
            throw RelayError.socket(errorMessage("send"))
        }
        offset += sent
    }
}

func connectThroughSOCKS(_ socket: Int32, host: String, port: UInt16) throws {
    let hostBytes = Array(host.utf8)
    guard hostBytes.count <= 255 else { throw RelayError.socks("SOCKS target hostname is too long") }

    try writeAll(socket, bytes: [5, 1, 0])
    guard try readExact(socket, count: 2) == [5, 0] else {
        throw RelayError.socks("SOCKS server rejected no-authentication mode")
    }

    var request: [UInt8] = [5, 1, 0, 3, UInt8(hostBytes.count)]
    request.append(contentsOf: hostBytes)
    request.append(UInt8(port >> 8))
    request.append(UInt8(port & 0xff))
    try writeAll(socket, bytes: request)

    let response = try readExact(socket, count: 4)
    guard response[0] == 5, response[1] == 0 else {
        throw RelayError.socks("SOCKS CONNECT failed with status \(response[1])")
    }
    switch response[3] {
    case 1: _ = try readExact(socket, count: 4)
    case 3: _ = try readExact(socket, count: Int(try readExact(socket, count: 1)[0]))
    case 4: _ = try readExact(socket, count: 16)
    default: throw RelayError.socks("SOCKS server returned an unknown address type")
    }
    _ = try readExact(socket, count: 2)
}

func copyStream(from source: Int32, to destination: Int32) {
    var buffer = [UInt8](repeating: 0, count: 32 * 1024)
    while true {
        let received = buffer.withUnsafeMutableBytes {
            Darwin.recv(source, $0.baseAddress, $0.count, 0)
        }
        if received == 0 { break }
        if received < 0 {
            if errno == EINTR { continue }
            break
        }
        do { try writeAll(destination, bytes: Array(buffer[0..<received])) } catch { break }
    }
    Darwin.shutdown(destination, SHUT_WR)
}

func handleClient(_ client: Int32, configuration: Configuration) {
    do {
        let upstream = try openTCP(host: configuration.socksHost, port: configuration.socksPort, listener: false)
        do {
            try connectThroughSOCKS(upstream, host: configuration.targetHost, port: configuration.targetPort)
        } catch {
            Darwin.close(upstream)
            throw error
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { copyStream(from: client, to: upstream); group.leave() }
        group.enter()
        DispatchQueue.global().async { copyStream(from: upstream, to: client); group.leave() }
        group.notify(queue: .global()) { Darwin.close(client); Darwin.close(upstream) }
    } catch {
        Darwin.close(client)
        FileHandle.standardError.write(Data("connection failed: \(error)\n".utf8))
    }
}

do {
    signal(SIGPIPE, SIG_IGN)
    let configuration = try Configuration.parse(CommandLine.arguments)
    let listener = try openTCP(host: configuration.listenHost, port: configuration.listenPort, listener: true)
    while true {
        let client = Darwin.accept(listener, nil, nil)
        if client < 0 {
            if errno == EINTR { continue }
            throw RelayError.socket(errorMessage("accept"))
        }
        configureSocket(client)
        DispatchQueue.global().async { handleClient(client, configuration: configuration) }
    }
} catch {
    FileHandle.standardError.write(Data("fatal: \(error)\n".utf8))
    exit(1)
}

#!/bin/sh

set -eu

RELEASE_BASE=https://github.com/OkamiFeng/typeless-relay/releases/latest/download
ARCHIVE=typeless-relay-arm64.tar.gz
CHECKSUM=typeless-relay-arm64.tar.gz.sha256

validate_port() {
    case "${1-}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

if [ "$(uname -s)" != Darwin ]; then
    echo 'Typeless Relay only supports macOS.' >&2
    exit 1
fi
if [ "$(uname -m)" != arm64 ]; then
    echo 'Typeless Relay only supports Apple Silicon Macs.' >&2
    exit 1
fi

SOCKS_PORT=
if [ "$#" -eq 0 ]; then
    :
elif [ "$#" -eq 2 ] && [ "$1" = '--socks-port' ]; then
    SOCKS_PORT=$2
    if ! validate_port "$SOCKS_PORT"; then
        echo "Invalid SOCKS port: $SOCKS_PORT" >&2
        exit 2
    fi
else
    echo 'Usage: install.sh [--socks-port PORT]' >&2
    exit 2
fi

TEMP_DIR=$(mktemp -d /private/tmp/typeless-relay-install.XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
cd "$TEMP_DIR"

echo 'Downloading Typeless Relay...'
curl -fsSL "$RELEASE_BASE/$ARCHIVE" -o "$ARCHIVE"
curl -fsSL "$RELEASE_BASE/$CHECKSUM" -o "$CHECKSUM"
shasum -a 256 -c "$CHECKSUM"
tar -xzf "$ARCHIVE"

if [ -n "$SOCKS_PORT" ]; then
    sudo /bin/sh release/install-release.sh --socks-port "$SOCKS_PORT"
else
    sudo /bin/sh release/install-release.sh
fi

echo 'Typeless Relay installed. Run: tlr test'

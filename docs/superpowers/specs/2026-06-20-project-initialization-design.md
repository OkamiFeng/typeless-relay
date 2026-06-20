# Typeless Relay 项目初始化设计

## 目标

建立公开仓库 `OkamiFeng/typeless-relay`，以 MIT 许可证发布一个仅支持 Apple Silicon macOS 的本地转发工具。工具让 Typeless 在 Clash TUN 关闭时，仍可通过 Clash 的本地 SOCKS5/Mixed 端口访问 `api.typeless.com`。

首版同时提供双击安装的 macOS `.pkg` 和 `curl | sh` 安装方式，并提供 `tlr install/uninstall/purge/start/stop/status/test/log/config` 管理命令。

## 项目边界

- 支持 macOS 13 及以上版本，CPU 架构仅为 `arm64`。
- 默认连接 Clash 的 `127.0.0.1:7890` SOCKS5/Mixed 端口；用户可在安装时或安装后将端口修改为任意有效 TCP 端口。
- 本地仅监听 `127.0.0.1:443`，并只转发到 `api.typeless.com:443`。
- 仅做原始 TCP 双向转发，不解密、不替换、不检查 TLS 内容。
- 不负责安装或配置 Clash，也不启用 TUN。
- 首版不提供 Homebrew Formula、图形管理界面或 Intel 架构产物。

## 仓库结构

```text
typeless-relay/
├── .github/workflows/
│   ├── ci.yml
│   └── release.yml
├── Sources/TypelessRelay/main.swift
├── Tests/relay_integration_test.rb
├── packaging/
│   ├── com.local.typeless-proxy-relay.plist.template
│   └── scripts/postinstall
├── scripts/
│   ├── build.sh
│   ├── install-system.sh
│   ├── purge-system.sh
│   ├── uninstall-system.sh
│   └── package.sh
├── bin/tlr
├── docs/superpowers/specs/
├── .gitignore
├── LICENSE
├── Makefile
├── Package.swift
├── README.md
└── install.sh
```

各文件职责保持单一：Swift 源码负责 relay；`tlr` 负责用户命令；system 脚本负责需要 root 权限的系统变更；`package.sh` 只生成发布产物；仓库根目录的 `install.sh` 负责网络下载安装。

## 运行架构

安装时向 `/etc/hosts` 写入带边界标记的 `127.0.0.1 api.typeless.com`，并通过 LaunchDaemon 启动 relay。Typeless 连接本机 443 端口后，relay 使用 SOCKS5 域名请求连接用户配置的 Clash 端口；Clash 根据域名规则选择代理节点，再由 relay 双向搬运 TCP 字节流。

LaunchDaemon 使用 `RunAtLoad` 与 `KeepAlive`，因此开机自动运行。服务日志写入 `/var/log/typeless-proxy-relay.log`。

Clash 端口保存在 `/usr/local/etc/typeless-relay.conf`，配置格式为单行 `SOCKS_PORT=<端口>`。系统安装脚本校验端口为 `1` 至 `65535` 的十进制整数，并根据该配置渲染 LaunchDaemon plist；配置文件是端口设置的唯一数据源。

## 安装与卸载

### `.pkg`

`make package` 使用 `swift build -c release --arch arm64`、`pkgbuild` 和 `productbuild` 生成 arm64 安装包。安装包放置以下持久文件：

- `/usr/local/bin/tlr`
- `/usr/local/share/typeless-relay/` 下的 relay、plist 和系统安装/卸载脚本

`postinstall` 调用系统安装脚本，安装并启动 LaunchDaemon。

`.pkg` 使用默认端口 `7890`。安装完成后可用 `tlr config socks-port <端口>` 修改。

### `curl | sh`

仓库根目录 `install.sh` 从 `OkamiFeng/typeless-relay` 最新 GitHub Release 下载 arm64 发布归档和 SHA-256 文件，校验后安装持久文件并启动服务。默认端口安装命令为：

```sh
curl -fsSL https://raw.githubusercontent.com/OkamiFeng/typeless-relay/main/install.sh | sh
```

安装时指定端口的命令为：

```sh
curl -fsSL https://raw.githubusercontent.com/OkamiFeng/typeless-relay/main/install.sh | sh -s -- --socks-port 7891
```

脚本检查操作系统、CPU 架构、下载状态和校验和；没有可用 Release 时明确报错并退出，不进行部分安装。

### `tlr` 语义

- `tlr install [--socks-port <端口>]`：从持久安装载荷恢复 Hosts 规则、系统二进制、plist 和 LaunchDaemon；指定端口时同时更新持久配置。
- `tlr config socks-port <端口>`：校验并持久化新端口，重新渲染 plist，然后自动重启服务使配置立即生效。
- `tlr uninstall`：停止服务并删除 Hosts 规则、系统二进制、plist、日志和 Hosts 备份。
- `tlr uninstall` 保留端口配置、`/usr/local/bin/tlr` 与 `/usr/local/share/typeless-relay`，确保之后仍能用原配置执行 `tlr install`。
- `tlr purge`：执行完全卸载，删除普通卸载涉及的所有内容，并额外删除端口配置、持久安装载荷、`tlr` 自身和标识符为 `com.okamifeng.typeless-relay` 的 macOS Installer receipt。
- `tlr purge` 先把独立清理脚本复制到 `/private/tmp`，再以 root 执行；这样删除正在使用的 `tlr` 和安装载荷后仍能完成余下清理。退出前删除临时脚本和临时目录。
- `start/stop/status/test/log` 延续现有行为。

安装、重新安装和卸载都必须幂等；Hosts 标记块始终至多一份，脚本使用临时文件原子替换 Hosts 内容。

`purge` 的“完全卸载”范围是本项目安装到系统的所有文件、配置和 receipt，不删除用户自行克隆的 Git 仓库、下载目录或 GitHub Release 安装包。

## 错误处理与安全

- 涉及系统目录和 LaunchDaemon 的操作统一要求 `sudo`。
- 所有接收端口参数的入口采用同一校验规则，拒绝空值、非数字、零和大于 `65535` 的数值。
- 安装前完成平台和输入文件校验，失败时返回非零状态。
- 系统脚本以 `set -eu` 运行，并使用 `trap` 清理临时文件。
- relay 无法连接 Clash 时记录错误并关闭对应客户端连接，不持有失效连接。
- 发布归档必须附 SHA-256；网络安装脚本在校验通过前不执行归档内脚本。
- Hosts 修改仅处理项目自己的起止标记块，不覆盖用户的其他条目。
- 系统脚本兼容清理原型版使用的 `CODEX TYPELESS RELAY` Hosts 标记，避免升级后产生重复映射。

## 测试与发布

- Ruby 集成测试启动假 SOCKS5 服务，验证域名目标、端口和双向数据转发。
- CI 检查 Swift 构建、集成测试、shell 语法、plist 语法以及安装包构建。
- `v*` 标签触发 Release 工作流，生成 `.pkg`、`.tar.gz` 和对应 SHA-256 文件，并附加到 GitHub Release。
- 本地验收包括实际卸载/安装闭环、自定义端口切换、完全卸载、重新安装、LaunchDaemon 状态、`127.0.0.1:443` 监听、Typeless API HTTP 响应和 Clash TUN 关闭状态。
- 从当前原型版迁移时，精确删除 `~/.zshrc` 中旧的 `tlr()` 函数和 `~/.local/share/typeless-relay` 旧载荷，确保 `/usr/local/bin/tlr` 是唯一命令实现。

## 文档要求

README 使用中文，包含功能原理、前置条件、两种安装方式、自定义 Clash 端口、所有 `tlr` 命令、普通卸载与完全卸载的区别、构建测试方式、故障排查和安全说明。

README 的项目缘起保留以下原文：

> 一觉醒来，发现typeless不开tun模式就连不上了，一怒之下就有了这个项目

## Git 与 GitHub

本地仓库主分支为 `main`。实现和验证完成后创建公开 GitHub 仓库 `OkamiFeng/typeless-relay`，设置为 `origin` 并推送；初始化过程不创建 Release。

# Typeless Relay 项目初始化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立可公开发布的 Apple Silicon macOS Typeless Relay 项目，提供 Swift 源码、`tlr` 管理命令、可配置 Clash 端口、普通与完全卸载、`.pkg` 和 `curl | sh` 安装方式。

**Architecture:** Swift relay 在 `127.0.0.1:443` 与用户配置的 Clash SOCKS5/Mixed 端口之间转发原始 TCP；root 系统脚本负责 Hosts、LaunchDaemon 和持久配置，`tlr` 只负责参数解析与调用这些脚本。发布流程从同一份 payload 生成 `.pkg` 与校验过的 `.tar.gz`，GitHub Actions 在官方 `macos-14` arm64 runner 上验证并构建。

**Tech Stack:** Swift 5.9+/Swift Package Manager、POSIX shell、Ruby、launchd、pkgbuild/productbuild、GitHub Actions、GitHub CLI。

---

## 文件职责

- `Package.swift`：声明 macOS 13+ 的 `typeless-proxy-relay` 可执行产品。
- `Sources/TypelessRelay/main.swift`：SOCKS5 握手与双向 TCP relay。
- `Tests/relay_integration_test.rb`：验证 SOCKS5 域名目标、自定义端口和双向数据流。
- `Tests/config_test.sh`：验证端口解析、配置读写和 plist 渲染。
- `Tests/tlr_test.sh`：在 mock 系统命令下验证 `tlr` 子命令及 purge 暂存行为。
- `scripts/common.sh`：共享端口校验、配置读取和 Hosts 标记处理函数。
- `scripts/install-system.sh`：安装/更新系统 relay、配置、Hosts 和 LaunchDaemon。
- `scripts/uninstall-system.sh`：普通卸载系统集成，保留 CLI、payload 和端口配置。
- `scripts/purge-system.sh`：完全删除所有项目安装痕迹并忘记 pkg receipt。
- `bin/tlr`：稳定的用户命令入口。
- `packaging/com.local.typeless-proxy-relay.plist.template`：包含 `__SOCKS_PORT__` 的 launchd 模板。
- `packaging/scripts/postinstall`：`.pkg` 安装后的服务启用入口。
- `scripts/build.sh`：生成 arm64 release binary。
- `scripts/package.sh`：组装共享 payload、`.pkg`、发布归档和 SHA-256。
- `install.sh`：从 GitHub 最新 Release 下载、校验并安装发布归档。
- `Makefile`：统一 build/test/package/release 命令。
- `.github/workflows/ci.yml`：每次推送和 PR 的构建测试。
- `.github/workflows/release.yml`：`v*` 标签发布三个构建产物及校验文件。

### Task 1：建立 Swift Package 和回归测试

**Files:**
- Create: `.gitignore`
- Create: `Package.swift`
- Create: `Sources/TypelessRelay/main.swift`
- Create: `Tests/relay_integration_test.rb`
- Create: `scripts/build.sh`
- Create: `Makefile`

- [ ] **Step 1：先复制集成测试并让它因缺少标准构建产物而失败**

```sh
mkdir -p Sources/TypelessRelay Tests scripts
cp ../work/typeless-relay/tests/relay_integration_test.rb Tests/relay_integration_test.rb
perl -0pi -e 's#File\.join\(ROOT, "build", "typeless-proxy-relay"\)#File.join(ROOT, ".build", "release", "typeless-proxy-relay")#' Tests/relay_integration_test.rb
/usr/bin/ruby Tests/relay_integration_test.rb
```

Expected: exit non-zero，输出 `relay binary missing`。

- [ ] **Step 2：创建 Swift Package 清单和源码**

`Package.swift`：

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "typeless-relay",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "typeless-proxy-relay", targets: ["TypelessRelay"])
    ],
    targets: [
        .executableTarget(name: "TypelessRelay", path: "Sources/TypelessRelay")
    ]
)
```

源码直接采用已验证实现，避免在项目初始化时重写网络核心：

```sh
cp ../work/typeless-relay/Sources/main.swift Sources/TypelessRelay/main.swift
```

- [ ] **Step 3：添加确定性构建入口**

`scripts/build.sh`：

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build -c release --arch arm64
file .build/release/typeless-proxy-relay | grep -q 'arm64'
```

`Makefile` 的首版目标：

```make
.PHONY: build test

build:
	./scripts/build.sh

test: build
	/usr/bin/ruby Tests/relay_integration_test.rb
```

- [ ] **Step 4：添加仓库忽略规则并清除 Finder 元数据**

`.gitignore`：

```gitignore
.DS_Store
.build/
dist/
*.pkg
*.tar.gz
*.sha256
```

Run: `find . -name .DS_Store -delete`

- [ ] **Step 5：运行构建和集成测试**

Run: `make test`

Expected: binary 为 arm64，测试输出 `PASS: SOCKS5 domain target and bidirectional relay`。

- [ ] **Step 6：提交 Swift 项目骨架**

```sh
git add .gitignore Package.swift Sources Tests/relay_integration_test.rb scripts/build.sh Makefile
git commit -m "feat: add Swift relay package"
```

### Task 2：实现端口配置和 launchd 模板渲染

**Files:**
- Create: `Tests/config_test.sh`
- Create: `scripts/common.sh`
- Create: `packaging/com.local.typeless-proxy-relay.plist.template`

- [ ] **Step 1：编写端口与模板的失败测试**

`Tests/config_test.sh` 覆盖以下精确断言：

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/common.sh"

validate_port 1
validate_port 7890
validate_port 65535
for invalid in '' 0 65536 abc 78.90 -1; do
    if validate_port "$invalid"; then
        echo "accepted invalid port: $invalid" >&2
        exit 1
    fi
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
write_config "$TMP/typeless-relay.conf" 7891
[ "$(read_config_port "$TMP/typeless-relay.conf")" = 7891 ]
render_plist "$ROOT/packaging/com.local.typeless-proxy-relay.plist.template" "$TMP/service.plist" 7891
plutil -lint "$TMP/service.plist" >/dev/null
grep -q '<string>7891</string>' "$TMP/service.plist"
! grep -q '__SOCKS_PORT__' "$TMP/service.plist"
echo 'PASS: port validation and plist rendering'
```

Run: `/bin/sh Tests/config_test.sh`

Expected: FAIL，因为 `scripts/common.sh` 尚不存在。

- [ ] **Step 2：实现共享配置函数**

`scripts/common.sh` 必须提供以下接口和行为：

```sh
validate_port() {
    case "${1-}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

read_config_port() {
    config_file=$1
    [ -f "$config_file" ] || return 1
    port=$(awk -F= '$1 == "SOCKS_PORT" { print $2; exit }' "$config_file")
    validate_port "$port" || return 1
    printf '%s\n' "$port"
}

write_config() {
    config_file=$1
    port=$2
    validate_port "$port" || return 1
    config_dir=$(dirname -- "$config_file")
    mkdir -p "$config_dir"
    temp=$(mktemp "$config_dir/.typeless-relay.conf.XXXXXX")
    printf 'SOCKS_PORT=%s\n' "$port" > "$temp"
    chmod 644 "$temp"
    if ! mv -f "$temp" "$config_file"; then
        rm -f "$temp"
        return 1
    fi
}

render_plist() {
    template=$1
    destination=$2
    port=$3
    validate_port "$port" || return 1
    sed "s/__SOCKS_PORT__/$port/g" "$template" > "$destination"
}
```

- [ ] **Step 3：创建 plist 模板**

从已验证 plist 复制结构，只做一项参数化：

```sh
mkdir -p packaging
cp ../work/typeless-relay/install/com.local.typeless-proxy-relay.plist packaging/com.local.typeless-proxy-relay.plist.template
perl -0pi -e 's#<string>7890</string>#<string>__SOCKS_PORT__</string>#' packaging/com.local.typeless-proxy-relay.plist.template
```

- [ ] **Step 4：运行配置测试并接入 Makefile**

Run: `/bin/sh Tests/config_test.sh`

Expected: `PASS: port validation and plist rendering`。

在 `Makefile` 的 `test` 目标追加：

```make
	/bin/sh Tests/config_test.sh
```

- [ ] **Step 5：提交配置能力**

```sh
git add Tests/config_test.sh scripts/common.sh packaging Makefile
git commit -m "feat: add configurable Clash port"
```

### Task 3：实现幂等的系统安装、普通卸载和完全卸载

**Files:**
- Create: `scripts/install-system.sh`
- Create: `scripts/uninstall-system.sh`
- Create: `scripts/purge-system.sh`
- Create: `Tests/system_scripts_test.sh`

- [ ] **Step 1：编写系统脚本静态契约测试**

`Tests/system_scripts_test.sh`：

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for script in install-system.sh uninstall-system.sh purge-system.sh; do
    /bin/sh -n "$ROOT/scripts/$script"
done
grep -q 'BEGIN TYPELESS RELAY' "$ROOT/scripts/install-system.sh"
grep -q 'CODEX TYPELESS RELAY' "$ROOT/scripts/install-system.sh"
grep -q 'SOCKS_PORT' "$ROOT/scripts/install-system.sh"
grep -q 'launchctl bootstrap' "$ROOT/scripts/install-system.sh"
grep -q 'launchctl bootout' "$ROOT/scripts/uninstall-system.sh"
grep -q '/usr/local/bin/tlr' "$ROOT/scripts/purge-system.sh"
grep -q 'pkgutil --forget com.okamifeng.typeless-relay' "$ROOT/scripts/purge-system.sh"
echo 'PASS: system script contracts'
```

Run: `/bin/sh Tests/system_scripts_test.sh`

Expected: FAIL，因为三个系统脚本不存在。

- [ ] **Step 2：实现 `install-system.sh`**

脚本完整骨架如下；实现时仅允许为 shell 兼容性作等价调整：

```sh
#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo 'Run with sudo.' >&2; exit 1; }
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"
PAYLOAD=$(dirname -- "$SCRIPT_DIR")
CONFIG=/usr/local/etc/typeless-relay.conf
PORT=
if [ "${1-}" = --socks-port ] && [ "$#" -eq 2 ]; then PORT=$2
elif [ "$#" -ne 0 ]; then echo 'Usage: install-system.sh [--socks-port PORT]' >&2; exit 2
elif PORT=$(read_config_port "$CONFIG" 2>/dev/null); then :
else PORT=7890
fi
validate_port "$PORT" || { echo "Invalid SOCKS port: $PORT" >&2; exit 2; }

LABEL=com.local.typeless-proxy-relay
BINARY_SOURCE=$PAYLOAD/bin/typeless-proxy-relay
TEMPLATE=$PAYLOAD/packaging/$LABEL.plist.template
BINARY_DEST=/usr/local/libexec/typeless-proxy-relay
PLIST_DEST=/Library/LaunchDaemons/$LABEL.plist
HOSTS_BACKUP=/var/backups/hosts.typeless-proxy-relay.before
HOSTS_TEMP=$(mktemp /var/tmp/typeless-relay-hosts.XXXXXX)
PLIST_TEMP=$(mktemp /var/tmp/typeless-relay-plist.XXXXXX)
trap 'rm -f "$HOSTS_TEMP" "$PLIST_TEMP"' EXIT HUP INT TERM

[ -x "$BINARY_SOURCE" ]
[ -f "$TEMPLATE" ]
install -d -o root -g wheel -m 755 /usr/local/libexec /usr/local/etc /var/backups
[ -f "$HOSTS_BACKUP" ] || install -o root -g wheel -m 644 /etc/hosts "$HOSTS_BACKUP"
awk '
    $0 == "# BEGIN TYPELESS RELAY" || $0 == "# BEGIN CODEX TYPELESS RELAY" { skipping = 1; next }
    $0 == "# END TYPELESS RELAY" || $0 == "# END CODEX TYPELESS RELAY" { skipping = 0; next }
    !skipping { print }
    END {
        print "# BEGIN TYPELESS RELAY"
        print "127.0.0.1 api.typeless.com"
        print "# END TYPELESS RELAY"
    }
' /etc/hosts > "$HOSTS_TEMP"
write_config "$CONFIG" "$PORT"
render_plist "$TEMPLATE" "$PLIST_TEMP" "$PORT"
plutil -lint "$PLIST_TEMP" >/dev/null
launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
install -o root -g wheel -m 755 "$BINARY_SOURCE" "$BINARY_DEST"
install -o root -g wheel -m 644 "$PLIST_TEMP" "$PLIST_DEST"
install -o root -g wheel -m 644 "$HOSTS_TEMP" /etc/hosts
launchctl enable "system/$LABEL"
launchctl bootstrap system "$PLIST_DEST"
launchctl kickstart -k "system/$LABEL"
dscacheutil -flushcache
killall -HUP mDNSResponder >/dev/null 2>&1 || true
```

- [ ] **Step 3：实现 `uninstall-system.sh`**

脚本只删除服务集成，完整核心如下：

```sh
#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo 'Run with sudo.' >&2; exit 1; }
LABEL=com.local.typeless-proxy-relay
HOSTS_TEMP=$(mktemp /var/tmp/typeless-relay-hosts.XXXXXX)
trap 'rm -f "$HOSTS_TEMP"' EXIT HUP INT TERM
launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
awk '
    $0 == "# BEGIN TYPELESS RELAY" || $0 == "# BEGIN CODEX TYPELESS RELAY" { skipping = 1; next }
    $0 == "# END TYPELESS RELAY" || $0 == "# END CODEX TYPELESS RELAY" { skipping = 0; next }
    !skipping { print }
' /etc/hosts > "$HOSTS_TEMP"
install -o root -g wheel -m 644 "$HOSTS_TEMP" /etc/hosts
rm -f /usr/local/libexec/typeless-proxy-relay \
  "/Library/LaunchDaemons/$LABEL.plist" \
  /var/log/typeless-proxy-relay.log \
  /var/backups/hosts.typeless-proxy-relay.before
dscacheutil -flushcache
killall -HUP mDNSResponder >/dev/null 2>&1 || true
```

它不得删除以下三个路径：

```text
/usr/local/bin/tlr
/usr/local/share/typeless-relay
/usr/local/etc/typeless-relay.conf
```

- [ ] **Step 4：实现 `purge-system.sh`**

```sh
#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo 'Run with sudo.' >&2; exit 1; }
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
/bin/sh "$SCRIPT_DIR/uninstall-system.sh"
rm -f /usr/local/etc/typeless-relay.conf /usr/local/bin/tlr
rm -rf /usr/local/share/typeless-relay
pkgutil --forget com.okamifeng.typeless-relay >/dev/null 2>&1 || true
```

- [ ] **Step 5：运行脚本契约和全部既有测试**

Run: `/bin/sh Tests/system_scripts_test.sh && make test`

Expected: 三个 PASS，且无 shell/plist 语法错误。

- [ ] **Step 6：提交系统生命周期脚本**

```sh
git add scripts/install-system.sh scripts/uninstall-system.sh scripts/purge-system.sh Tests/system_scripts_test.sh Makefile
git commit -m "feat: manage relay system lifecycle"
```

### Task 4：实现 `tlr` 命令及自删除 purge 流程

**Files:**
- Create: `Tests/tlr_test.sh`
- Create: `bin/tlr`

- [ ] **Step 1：编写 mock 驱动的 CLI 失败测试**

测试建立临时 `PATH`，mock `sudo`、`launchctl`、`curl`、`nc`、`tail`，并通过 `TLR_PAYLOAD` 指向测试 payload。必须断言：

```text
tlr install                         -> sudo install-system.sh
tlr install --socks-port 7891       -> sudo install-system.sh --socks-port 7891
tlr config socks-port 7892          -> sudo install-system.sh --socks-port 7892
tlr uninstall                       -> sudo uninstall-system.sh
tlr purge                           -> 在 /private/tmp 暂存 purge/common/uninstall 后调用 sudo
tlr install --socks-port 0          -> exit 2
tlr config socks-port abc           -> exit 2
tlr unknown                         -> exit 2
```

Run: `/bin/sh Tests/tlr_test.sh`

Expected: FAIL，因为 `bin/tlr` 尚不存在。

- [ ] **Step 2：实现 CLI 公共入口和帮助**

`bin/tlr` 使用 POSIX shell，常量与分派骨架为：

```sh
#!/bin/sh
set -u

LABEL=com.local.typeless-proxy-relay
SERVICE=system/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
LOG_FILE=/var/log/typeless-proxy-relay.log
PAYLOAD=${TLR_PAYLOAD:-/usr/local/share/typeless-relay}
. "$PAYLOAD/scripts/common.sh"

usage() {
    echo 'Usage: tlr {install [--socks-port PORT]|config socks-port PORT|uninstall|purge|start|stop|status|test|log [LINE_COUNT]}'
}
```

`install` 与 `config socks-port` 在 sudo 前调用 `validate_port`；`start/stop/status/test/log` 保留现有 zsh 函数行为，但改写为 POSIX shell。`test` 同时验证 service、443、API 和 Clash TUN；缺少 `jq` 或 Clash socket 时输出 WARN，不把它误报为 TUN 已关闭。

- [ ] **Step 3：实现安全的 purge 暂存**

`tlr purge` 必须：

```sh
stage=$(mktemp -d /private/tmp/typeless-relay-purge.XXXXXX) || exit 1
trap 'rm -rf "$stage"' EXIT HUP INT TERM
cp "$PAYLOAD/scripts/common.sh" "$stage/common.sh"
cp "$PAYLOAD/scripts/uninstall-system.sh" "$stage/uninstall-system.sh"
cp "$PAYLOAD/scripts/purge-system.sh" "$stage/purge-system.sh"
sudo /bin/sh "$stage/purge-system.sh"
```

这样 root 清理 payload 和 `tlr` 后，当前暂存脚本仍可完成清理并返回结果。

- [ ] **Step 4：运行 CLI 与全套测试**

Run: `/bin/sh Tests/tlr_test.sh && make test`

Expected: CLI 测试和 relay/config/system 测试全部 PASS。

- [ ] **Step 5：提交 CLI**

```sh
git add bin/tlr Tests/tlr_test.sh Makefile
git commit -m "feat: add tlr management command"
```

### Task 5：生成共享发布载荷、`.pkg` 和 tar 归档

**Files:**
- Create: `packaging/scripts/postinstall`
- Create: `scripts/package.sh`
- Modify: `Makefile`
- Create: `Tests/package_test.sh`

- [ ] **Step 1：编写发布产物失败测试**

`Tests/package_test.sh` 执行 `make package VERSION=0.1.0` 后断言：

```sh
[ -f dist/typeless-relay-0.1.0-arm64.pkg ]
[ -f dist/typeless-relay-arm64.tar.gz ]
[ -f dist/typeless-relay-arm64.tar.gz.sha256 ]
pkgutil --check-signature dist/typeless-relay-0.1.0-arm64.pkg >/dev/null 2>&1 || true
tar -tzf dist/typeless-relay-arm64.tar.gz | grep -q 'release/install-release.sh'
(cd dist && shasum -a 256 -c typeless-relay-arm64.tar.gz.sha256)
```

Run: `/bin/sh Tests/package_test.sh`

Expected: FAIL，因为 package 目标不存在。

- [ ] **Step 2：实现 pkg postinstall**

`packaging/scripts/postinstall`：

```sh
#!/bin/sh
set -eu
exec /bin/sh /usr/local/share/typeless-relay/scripts/install-system.sh
```

- [ ] **Step 3：实现确定的 payload 组装与 pkg 构建**

`scripts/package.sh` 接收唯一参数 VERSION，拒绝空值；清理并创建 `dist/work/root`，将以下文件装入对应路径并设置权限：

```text
/usr/local/bin/tlr
/usr/local/share/typeless-relay/bin/typeless-proxy-relay
/usr/local/share/typeless-relay/scripts/common.sh
/usr/local/share/typeless-relay/scripts/install-system.sh
/usr/local/share/typeless-relay/scripts/uninstall-system.sh
/usr/local/share/typeless-relay/scripts/purge-system.sh
/usr/local/share/typeless-relay/packaging/com.local.typeless-proxy-relay.plist.template
```

随后执行：

```sh
pkgbuild --root dist/work/root \
  --scripts packaging/scripts \
  --identifier com.okamifeng.typeless-relay \
  --version "$VERSION" \
  dist/work/component.pkg
productbuild --package dist/work/component.pkg "dist/typeless-relay-$VERSION-arm64.pkg"
```

- [ ] **Step 4：组装网络安装归档**

在 `dist/work/release` 中放入与 pkg 相同的 `payload/`、`tlr` 及 `install-release.sh`。`install-release.sh` 校验 root 身份后把 CLI 与 payload 安装到 `/usr/local`，再调用：

```sh
/bin/sh /usr/local/share/typeless-relay/scripts/install-system.sh "$@"
```

生成固定名称归档与校验：

```sh
tar -C dist/work -czf dist/typeless-relay-arm64.tar.gz release
(cd dist && shasum -a 256 typeless-relay-arm64.tar.gz > typeless-relay-arm64.tar.gz.sha256)
```

- [ ] **Step 5：接入 Makefile 并运行产物测试**

```make
package: build
	./scripts/package.sh "$(VERSION)"

clean:
	rm -rf .build dist
```

Run: `/bin/sh Tests/package_test.sh`

Expected: `.pkg`、tar 和 SHA-256 均存在，校验通过。

- [ ] **Step 6：提交打包能力**

```sh
git add packaging/scripts scripts/package.sh Tests/package_test.sh Makefile
git commit -m "feat: build macOS installer artifacts"
```

### Task 6：实现 GitHub Release 网络安装器

**Files:**
- Create: `install.sh`
- Create: `Tests/network_installer_test.sh`
- Modify: `Makefile`

- [ ] **Step 1：编写安装器参数和静态安全测试**

`Tests/network_installer_test.sh` 断言：shell 语法有效；`--socks-port 1/65535` 被接受；`0/65536/abc` 返回 2；脚本包含固定 GitHub latest/download URL、`shasum -a 256 -c`、临时目录 trap，并且校验发生在调用 `install-release.sh` 之前。

Run: `/bin/sh Tests/network_installer_test.sh`

Expected: FAIL，因为根目录 `install.sh` 不存在。

- [ ] **Step 2：实现平台、参数、下载和校验流程**

`install.sh` 使用以下常量：

```sh
RELEASE_BASE=https://github.com/OkamiFeng/typeless-relay/releases/latest/download
ARCHIVE=typeless-relay-arm64.tar.gz
CHECKSUM=typeless-relay-arm64.tar.gz.sha256
```

执行顺序：确认 `uname -s` 为 Darwin、`uname -m` 为 arm64；解析可选 `--socks-port PORT` 并使用脚本内同等规则校验；创建临时目录与 trap；`curl -fL` 下载 archive/checksum；在临时目录运行 `shasum -a 256 -c`；解压；最后执行 `sudo /bin/sh release/install-release.sh` 并原样传递端口参数。任何失败必须在安装系统文件之前退出。

- [ ] **Step 3：运行安装器和全套非破坏性测试**

Run: `/bin/sh Tests/network_installer_test.sh && make test`

Expected: 所有测试 PASS，测试过程不修改 `/etc/hosts` 或 launchd。

- [ ] **Step 4：提交网络安装器**

```sh
git add install.sh Tests/network_installer_test.sh Makefile
git commit -m "feat: add verified release installer"
```

### Task 7：补齐 README、MIT 许可证和 GitHub 工作流

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`

- [ ] **Step 1：编写中文 README**

README 按以下顺序包含完整章节：项目缘起、工作原理、要求、`.pkg` 安装、`curl | sh` 安装、自定义 Clash 端口、命令表、普通卸载与完全卸载、源码构建、测试、故障排查、安全说明、许可证。

项目缘起必须原样包含：

```text
一觉醒来，发现typeless不开tun模式就连不上了，一怒之下就有了这个项目
```

端口示例必须同时包含：

```sh
tlr install --socks-port 7891
tlr config socks-port 7891
curl -fsSL https://raw.githubusercontent.com/OkamiFeng/typeless-relay/main/install.sh | sh -s -- --socks-port 7891
```

卸载章节明确 `tlr uninstall` 保留 CLI/payload/config，`tlr purge` 删除全部系统安装痕迹但不删除用户自己克隆或下载的文件。

- [ ] **Step 2：添加 MIT LICENSE**

使用标准 MIT 文本，版权行为：

```text
Copyright (c) 2026 OkamiFeng
```

- [ ] **Step 3：添加 CI workflow**

`.github/workflows/ci.yml` 在 `push` 和 `pull_request` 上运行，使用官方 `macos-14` arm64 runner与 `actions/checkout@v4`，执行：

```sh
make test
make package VERSION=0.0.0
```

- [ ] **Step 4：添加 Release workflow**

`.github/workflows/release.yml` 仅在推送 `v*` 标签时运行，设置 `permissions: contents: write`，使用 `macos-14` 和 `actions/checkout@v4`。从 `${GITHUB_REF_NAME#v}` 取得版本，执行 `make test`、`make package VERSION="$VERSION"`，最后使用预装的 `gh`：

```sh
gh release create "$GITHUB_REF_NAME" \
  "dist/typeless-relay-$VERSION-arm64.pkg" \
  dist/typeless-relay-arm64.tar.gz \
  dist/typeless-relay-arm64.tar.gz.sha256 \
  --generate-notes
```

环境变量 `GH_TOKEN` 绑定 `${{ github.token }}`。本任务不推送 tag，不实际创建 Release。

- [ ] **Step 5：检查文档与 workflow 语法**

Run:

```sh
grep -q '一觉醒来，发现typeless不开tun模式就连不上了，一怒之下就有了这个项目' README.md
grep -q 'tlr purge' README.md
grep -q 'tlr config socks-port' README.md
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); YAML.load_file(".github/workflows/release.yml")'
git diff --check
```

Expected: 全部 exit 0。

- [ ] **Step 6：提交文档和自动化**

```sh
git add README.md LICENSE .github
git commit -m "docs: prepare public project release"
```

### Task 8：真实生命周期验收、创建公开仓库并推送

**Files:**
- Modify only if verification finds a directly related defect.

- [ ] **Step 1：运行完整非破坏性验证**

Run:

```sh
make clean
make test
make package VERSION=0.1.0
git diff --check
git status --short
```

Expected: 所有测试 PASS；三个发布文件存在；工作树仅包含预期提交状态。

- [ ] **Step 2：备份当前个人安装载荷并安装项目构建版本**

先将现有 `~/.local/share/typeless-relay` 复制到项目外的临时目录；再使用 `dist/work/release/install-release.sh --socks-port <当前配置端口>` 进行真实安装。该步骤需要用户完成一次管理员授权。

安装验证通过后，用精确范围补丁删除 `~/.zshrc` 中现有 `tlr()` 函数，并删除 `~/.local/share/typeless-relay` 原型载荷；重新启动 zsh 后用 `whence -a tlr` 确认命令解析到 `/usr/local/bin/tlr`。不得修改 `.zshrc` 的其他配置。

- [ ] **Step 3：验证安装、自定义端口和普通卸载闭环**

依次验证：`tlr test` 通过；`tlr config socks-port <测试 Clash 端口>` 后 plist 与配置一致；恢复实际 Clash 端口后 API 返回非 `000`；`tlr uninstall` 后服务、Hosts、system binary、plist、日志与备份消失，而 CLI、payload、config 保留；`tlr install` 后服务恢复且继续使用保存端口。

- [ ] **Step 4：验证 purge 的完全清理范围**

运行 `tlr purge` 后逐项确认以下路径/状态均不存在：LaunchDaemon service、Hosts 标记、`/usr/local/libexec/typeless-proxy-relay`、plist、日志、Hosts 备份、`/usr/local/etc/typeless-relay.conf`、`/usr/local/share/typeless-relay`、`/usr/local/bin/tlr`、`com.okamifeng.typeless-relay` receipt、`127.0.0.1:443` listener。

- [ ] **Step 5：重新安装最终版本并验证用户当前环境**

使用刚生成的 release installer 重新安装，恢复用户当前 Clash 端口，运行 `tlr test`，确认 TUN 仍为 false。此步骤保证项目验收不会把用户留在无法使用 Typeless 的状态。

- [ ] **Step 6：提交验证过程中必要的精准修复并确认历史**

```sh
git status --short
git log --oneline --decorate -10
```

若没有缺陷则不创建空提交；若有修复，每个修复使用与缺陷对应的测试和单独 commit。

- [ ] **Step 7：创建公开 GitHub 仓库并推送 main**

确认 `gh auth status` 显示有权访问 `OkamiFeng` 后执行：

```sh
gh repo create OkamiFeng/typeless-relay --public --source=. --remote=origin --push
```

Expected: `origin` 指向 `https://github.com/OkamiFeng/typeless-relay.git` 或对应 SSH URL；GitHub 默认分支为 `main`；仓库公开；没有 Release 和 tag。

- [ ] **Step 8：最终远端核验**

```sh
gh repo view OkamiFeng/typeless-relay --json nameWithOwner,visibility,defaultBranchRef,url
gh run list --repo OkamiFeng/typeless-relay --limit 5
git status --short
```

Expected: `visibility` 为 `PUBLIC`，默认分支为 `main`，首次 CI 已启动或完成，本地工作树干净。

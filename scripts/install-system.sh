#!/bin/sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo 'Run with sudo.' >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

PAYLOAD=$(dirname -- "$SCRIPT_DIR")
CONFIG=/usr/local/etc/typeless-relay.conf
LABEL=com.local.typeless-proxy-relay
BINARY_SOURCE=$PAYLOAD/bin/typeless-proxy-relay
TEMPLATE=$PAYLOAD/packaging/$LABEL.plist.template
BINARY_DEST=/usr/local/libexec/typeless-proxy-relay
PLIST_DEST=/Library/LaunchDaemons/$LABEL.plist
HOSTS_BACKUP=/var/backups/hosts.typeless-proxy-relay.before

PORT=
if [ "${1-}" = '--socks-port' ] && [ "$#" -eq 2 ]; then
    PORT=$2
elif [ "$#" -ne 0 ]; then
    echo 'Usage: install-system.sh [--socks-port PORT]' >&2
    exit 2
elif PORT=$(read_config_port "$CONFIG" 2>/dev/null); then
    :
else
    PORT=7890
fi

if ! validate_port "$PORT"; then
    echo "Invalid SOCKS port: $PORT" >&2
    exit 2
fi

HOSTS_TEMP=$(mktemp /var/tmp/typeless-relay-hosts.XXXXXX)
PLIST_TEMP=$(mktemp /var/tmp/typeless-relay-plist.XXXXXX)
trap 'rm -f "$HOSTS_TEMP" "$PLIST_TEMP"' EXIT HUP INT TERM

[ -x "$BINARY_SOURCE" ]
[ -f "$TEMPLATE" ]
install -d -o root -g wheel -m 755 /usr/local/libexec /usr/local/etc /var/backups
if [ ! -f "$HOSTS_BACKUP" ]; then
    install -o root -g wheel -m 644 /etc/hosts "$HOSTS_BACKUP"
fi

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
chown root:wheel "$CONFIG"
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

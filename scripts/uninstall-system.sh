#!/bin/sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo 'Run with sudo.' >&2
    exit 1
fi

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

rm -f \
    /usr/local/libexec/typeless-proxy-relay \
    "/Library/LaunchDaemons/$LABEL.plist" \
    /var/log/typeless-proxy-relay.log \
    /var/backups/hosts.typeless-proxy-relay.before
dscacheutil -flushcache
killall -HUP mDNSResponder >/dev/null 2>&1 || true

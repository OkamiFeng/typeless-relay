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

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
write_config "$TEMP_DIR/typeless-relay.conf" 7891
[ "$(read_config_port "$TEMP_DIR/typeless-relay.conf")" = 7891 ]
render_plist \
    "$ROOT/packaging/com.local.typeless-proxy-relay.plist.template" \
    "$TEMP_DIR/service.plist" \
    7891
plutil -lint "$TEMP_DIR/service.plist" >/dev/null
grep -q '<string>7891</string>' "$TEMP_DIR/service.plist"
! grep -q '__SOCKS_PORT__' "$TEMP_DIR/service.plist"

echo 'PASS: port validation and plist rendering'

#!/bin/sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo 'Run with sudo.' >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PAYLOAD_SOURCE=$SCRIPT_DIR/payload
PAYLOAD_DEST=/usr/local/share/typeless-relay

install -d -o root -g wheel -m 755 \
    /usr/local/bin \
    "$PAYLOAD_DEST/bin" \
    "$PAYLOAD_DEST/scripts" \
    "$PAYLOAD_DEST/packaging"
install -o root -g wheel -m 755 "$SCRIPT_DIR/tlr" /usr/local/bin/tlr
install -o root -g wheel -m 755 \
    "$PAYLOAD_SOURCE/bin/typeless-proxy-relay" \
    "$PAYLOAD_DEST/bin/typeless-proxy-relay"
install -o root -g wheel -m 644 \
    "$PAYLOAD_SOURCE/scripts/common.sh" \
    "$PAYLOAD_DEST/scripts/common.sh"
for script in install-system.sh uninstall-system.sh purge-system.sh; do
    install -o root -g wheel -m 755 \
        "$PAYLOAD_SOURCE/scripts/$script" \
        "$PAYLOAD_DEST/scripts/$script"
done
install -o root -g wheel -m 644 \
    "$PAYLOAD_SOURCE/packaging/com.local.typeless-proxy-relay.plist.template" \
    "$PAYLOAD_DEST/packaging/com.local.typeless-proxy-relay.plist.template"

exec /bin/sh "$PAYLOAD_DEST/scripts/install-system.sh" "$@"

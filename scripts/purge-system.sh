#!/bin/sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo 'Run with sudo.' >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
/bin/sh "$SCRIPT_DIR/uninstall-system.sh"

rm -f /usr/local/etc/typeless-relay.conf /usr/local/bin/tlr
rm -rf /usr/local/share/typeless-relay
pkgutil --forget com.okamifeng.typeless-relay >/dev/null 2>&1 || true

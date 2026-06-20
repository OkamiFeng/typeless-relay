#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

for script in install-system.sh uninstall-system.sh purge-system.sh; do
    /bin/sh -n "$ROOT/scripts/$script"
done

grep -q 'BEGIN TYPELESS RELAY' "$ROOT/scripts/install-system.sh"
grep -q 'CODEX TYPELESS RELAY' "$ROOT/scripts/install-system.sh"
grep -q -- '--socks-port' "$ROOT/scripts/install-system.sh"
grep -q 'write_config' "$ROOT/scripts/install-system.sh"
grep -q 'launchctl bootstrap' "$ROOT/scripts/install-system.sh"
grep -q 'launchctl bootout' "$ROOT/scripts/uninstall-system.sh"
grep -q 'CODEX TYPELESS RELAY' "$ROOT/scripts/uninstall-system.sh"
grep -q '/usr/local/bin/tlr' "$ROOT/scripts/purge-system.sh"
grep -q '/usr/local/share/typeless-relay' "$ROOT/scripts/purge-system.sh"
grep -q '/usr/local/etc/typeless-relay.conf' "$ROOT/scripts/purge-system.sh"
grep -q 'pkgutil --forget com.okamifeng.typeless-relay' "$ROOT/scripts/purge-system.sh"

echo 'PASS: system script contracts'

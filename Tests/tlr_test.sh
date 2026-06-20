#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
PAYLOAD=$TEMP_DIR/payload
MOCK_BIN=$TEMP_DIR/bin
LOG=$TEMP_DIR/sudo.log
mkdir -p "$PAYLOAD/scripts" "$MOCK_BIN"
cp "$ROOT/scripts/common.sh" "$PAYLOAD/scripts/common.sh"
cp "$ROOT/scripts/install-system.sh" "$PAYLOAD/scripts/install-system.sh"
cp "$ROOT/scripts/uninstall-system.sh" "$PAYLOAD/scripts/uninstall-system.sh"
cp "$ROOT/scripts/purge-system.sh" "$PAYLOAD/scripts/purge-system.sh"

cat > "$MOCK_BIN/sudo" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$TLR_TEST_LOG"
case "$*" in
    *purge-system.sh*)
        stage=$(dirname -- "$2")
        test -f "$stage/common.sh"
        test -f "$stage/uninstall-system.sh"
        test -f "$stage/purge-system.sh"
        ;;
esac
MOCK
chmod +x "$MOCK_BIN/sudo"

run_tlr() {
    PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
        TLR_PAYLOAD="$PAYLOAD" \
        TLR_TEST_LOG="$LOG" \
        /bin/sh "$ROOT/bin/tlr" "$@"
}

: > "$LOG"
run_tlr install >/dev/null
grep -q 'install-system.sh$' "$LOG"

: > "$LOG"
run_tlr install --socks-port 7891 >/dev/null
grep -q 'install-system.sh --socks-port 7891$' "$LOG"

: > "$LOG"
run_tlr config socks-port 7892 >/dev/null
grep -q 'install-system.sh --socks-port 7892$' "$LOG"

: > "$LOG"
run_tlr uninstall >/dev/null
grep -q 'uninstall-system.sh$' "$LOG"

: > "$LOG"
run_tlr purge >/dev/null
grep -q '/private/tmp/typeless-relay-purge\..*/purge-system.sh$' "$LOG"

for command in \
    'install --socks-port 0' \
    'install --socks-port 65536' \
    'config socks-port abc' \
    'unknown'; do
    if run_tlr $command >/dev/null 2>&1; then
        echo "accepted invalid command: $command" >&2
        exit 1
    fi
done

run_tlr help | grep -q 'tlr purge'
run_tlr help | grep -q 'tlr config socks-port PORT'

echo 'PASS: tlr command dispatch and validation'

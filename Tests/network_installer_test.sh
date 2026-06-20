#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
MOCK_BIN=$TEMP_DIR/bin
LOG=$TEMP_DIR/install.log
ASSETS=$TEMP_DIR/assets
mkdir -p "$MOCK_BIN" "$ASSETS" "$TEMP_DIR/fixture/release"
printf '#!/bin/sh\nexit 0\n' > "$TEMP_DIR/fixture/release/install-release.sh"
tar -C "$TEMP_DIR/fixture" -czf "$ASSETS/typeless-relay-arm64.tar.gz" release
(
    cd "$ASSETS"
    shasum -a 256 typeless-relay-arm64.tar.gz > typeless-relay-arm64.tar.gz.sha256
)

cat > "$MOCK_BIN/uname" <<'MOCK'
#!/bin/sh
case "$1" in
    -s) echo "${TLR_TEST_OS:-Darwin}" ;;
    -m) echo "${TLR_TEST_ARCH:-arm64}" ;;
esac
MOCK

cat > "$MOCK_BIN/curl" <<'MOCK'
#!/bin/sh
url=
destination=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) destination=$2; shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
    esac
done
case "$url" in
    *.sha256) cp "$TLR_TEST_DIST/typeless-relay-arm64.tar.gz.sha256" "$destination" ;;
    *.tar.gz) cp "$TLR_TEST_DIST/typeless-relay-arm64.tar.gz" "$destination" ;;
    *) exit 1 ;;
esac
MOCK

cat > "$MOCK_BIN/sudo" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$TLR_TEST_LOG"
MOCK
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/curl" "$MOCK_BIN/sudo"

run_installer() {
    PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
        TLR_TEST_DIST="$ASSETS" \
        TLR_TEST_LOG="$LOG" \
        /bin/sh "$ROOT/install.sh" "$@"
}

/bin/sh -n "$ROOT/install.sh"
: > "$LOG"
run_installer --socks-port 7891 >/dev/null
grep -q 'release/install-release.sh --socks-port 7891$' "$LOG"

for command in '--socks-port 0' '--socks-port 65536' '--socks-port abc' '--bad'; do
    if run_installer $command >/dev/null 2>&1; then
        echo "accepted invalid installer arguments: $command" >&2
        exit 1
    fi
done

if TLR_TEST_ARCH=x86_64 run_installer >/dev/null 2>&1; then
    echo 'accepted Intel architecture' >&2
    exit 1
fi

grep -q 'releases/latest/download' "$ROOT/install.sh"
grep -q 'shasum -a 256 -c' "$ROOT/install.sh"

echo 'PASS: verified network installer flow'

#!/bin/sh

set -eu

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo 'Usage: package.sh VERSION' >&2
    exit 2
fi
VERSION=$1
case "$VERSION" in
    *[!0-9A-Za-z.-]*) echo "Invalid version: $VERSION" >&2; exit 2 ;;
esac

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST=$ROOT/dist
WORK=$DIST/work
PKG_ROOT=$WORK/root
PAYLOAD=$PKG_ROOT/usr/local/share/typeless-relay
RELEASE=$WORK/release
RELEASE_PAYLOAD=$RELEASE/payload

sanitize_component_package() {
    component=$1
    expanded=$WORK/component-expanded
    payload_root=$WORK/component-payload
    cleaned=$WORK/component-clean.pkg

    rm -rf "$expanded" "$payload_root" "$cleaned"
    pkgutil --expand "$component" "$expanded"
    mkdir -p "$payload_root"
    (
        cd "$payload_root"
        gzip -dc "$expanded/Payload" | cpio -idm 2>/dev/null
    )
    find "$payload_root" -name '._*' -delete
    find "$expanded/Scripts" -name '._*' -delete
    (
        cd "$payload_root"
        find . -print | cpio -o -R root:wheel -H odc 2>/dev/null | gzip -c > "$expanded/Payload.new"
    )
    mv "$expanded/Payload.new" "$expanded/Payload"
    lsbom "$expanded/Bom" | awk '$1 !~ /(^|\/)\._/' > "$expanded/Bom.list"
    mkbom -i "$expanded/Bom.list" "$expanded/Bom"
    rm -f "$expanded/Bom.list"
    pkgutil --flatten "$expanded" "$cleaned"
    mv "$cleaned" "$component"
}

rm -rf "$DIST"
mkdir -p \
    "$PAYLOAD/bin" \
    "$PAYLOAD/scripts" \
    "$PAYLOAD/packaging" \
    "$PKG_ROOT/usr/local/bin" \
    "$RELEASE_PAYLOAD/bin" \
    "$RELEASE_PAYLOAD/scripts" \
    "$RELEASE_PAYLOAD/packaging"

install -m 755 "$ROOT/.build/release/typeless-proxy-relay" "$PAYLOAD/bin/typeless-proxy-relay"
install -m 755 "$ROOT/bin/tlr" "$PKG_ROOT/usr/local/bin/tlr"
install -m 644 "$ROOT/scripts/common.sh" "$PAYLOAD/scripts/common.sh"
for script in install-system.sh uninstall-system.sh purge-system.sh; do
    install -m 755 "$ROOT/scripts/$script" "$PAYLOAD/scripts/$script"
done
install -m 644 \
    "$ROOT/packaging/com.local.typeless-proxy-relay.plist.template" \
    "$PAYLOAD/packaging/com.local.typeless-proxy-relay.plist.template"

pkgbuild \
    --root "$PKG_ROOT" \
    --scripts "$ROOT/packaging/scripts" \
    --identifier com.okamifeng.typeless-relay \
    --version "$VERSION" \
    "$WORK/component.pkg"
sanitize_component_package "$WORK/component.pkg"
productbuild \
    --package "$WORK/component.pkg" \
    "$DIST/typeless-relay-$VERSION-arm64.pkg"

install -m 755 "$ROOT/packaging/install-release.sh" "$RELEASE/install-release.sh"
install -m 755 "$ROOT/bin/tlr" "$RELEASE/tlr"
install -m 755 "$ROOT/.build/release/typeless-proxy-relay" "$RELEASE_PAYLOAD/bin/typeless-proxy-relay"
install -m 644 "$ROOT/scripts/common.sh" "$RELEASE_PAYLOAD/scripts/common.sh"
for script in install-system.sh uninstall-system.sh purge-system.sh; do
    install -m 755 "$ROOT/scripts/$script" "$RELEASE_PAYLOAD/scripts/$script"
done
install -m 644 \
    "$ROOT/packaging/com.local.typeless-proxy-relay.plist.template" \
    "$RELEASE_PAYLOAD/packaging/com.local.typeless-proxy-relay.plist.template"

tar -C "$WORK" -czf "$DIST/typeless-relay-arm64.tar.gz" release
(
    cd "$DIST"
    shasum -a 256 typeless-relay-arm64.tar.gz > typeless-relay-arm64.tar.gz.sha256
)

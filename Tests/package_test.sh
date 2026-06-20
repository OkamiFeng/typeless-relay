#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

make package VERSION=0.1.0

[ -f dist/typeless-relay-0.1.0-arm64.pkg ]
[ -f dist/typeless-relay-arm64.tar.gz ]
[ -f dist/typeless-relay-arm64.tar.gz.sha256 ]
for package_file in dist/work/component.pkg dist/typeless-relay-0.1.0-arm64.pkg; do
    if pkgutil --payload-files "$package_file" | grep -q '/\._'; then
        echo "pkg contains AppleDouble metadata files: $package_file" >&2
        exit 1
    fi
done
if tar -tzf dist/typeless-relay-arm64.tar.gz | grep -q '/\._'; then
    echo 'release archive contains AppleDouble metadata files' >&2
    exit 1
fi
tar -tzf dist/typeless-relay-arm64.tar.gz | grep -q 'release/install-release.sh'
tar -tzf dist/typeless-relay-arm64.tar.gz | grep -q 'release/payload/bin/typeless-proxy-relay'
tar -tzf dist/typeless-relay-arm64.tar.gz | grep -q 'release/tlr'
(cd dist && shasum -a 256 -c typeless-relay-arm64.tar.gz.sha256)

echo 'PASS: macOS package and release archive'

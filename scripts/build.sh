#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build -c release --arch arm64
file .build/release/typeless-proxy-relay | grep -q 'arm64'

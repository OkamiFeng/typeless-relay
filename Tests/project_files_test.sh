#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

grep -q '一觉醒来，发现typeless不开tun模式就连不上了，一怒之下就有了这个项目' README.md
grep -q 'tlr config socks-port 7891' README.md
grep -q 'tlr purge' README.md
grep -q 'curl -fsSL https://raw.githubusercontent.com/OkamiFeng/typeless-relay/main/install.sh' README.md
grep -q 'MIT License' LICENSE
grep -q 'Copyright (c) 2026 OkamiFeng' LICENSE
grep -q 'macos-14' .github/workflows/ci.yml
grep -q 'actions/checkout@v7' .github/workflows/ci.yml
grep -q 'actions/checkout@v7' .github/workflows/release.yml
! grep -R -q 'actions/checkout@v4' .github/workflows
grep -q 'make package VERSION=0.0.0' .github/workflows/ci.yml
grep -q 'gh release create' .github/workflows/release.yml
grep -q 'permissions:' .github/workflows/release.yml

/usr/bin/ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); YAML.load_file(".github/workflows/release.yml")'

echo 'PASS: public project files'

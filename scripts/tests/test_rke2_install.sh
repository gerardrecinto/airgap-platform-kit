#!/usr/bin/env bash
# Exercises rke2-airgap-install.sh --dry-run against a fake staged directory.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../rke2-airgap-install.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

stage="$work/stage"
mkdir -p "$stage"
printf 'fake tarball\n' > "$stage/rke2.linux-amd64.tar.gz"
printf 'fake images\n' > "$stage/rke2-images.linux-amd64.tar.zst"
printf '#!/bin/sh\nexit 0\n' > "$stage/install.sh"
if command -v sha256sum >/dev/null 2>&1; then sum() { sha256sum "$@"; }; else sum() { shasum -a 256 "$@"; }; fi
(cd "$stage" && sum rke2.linux-amd64.tar.gz rke2-images.linux-amd64.tar.zst > sha256sum-amd64.txt)

pass=0
check() { printf 'ok: %s\n' "$1"; pass=$((pass + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

out="$("$script" --dir "$stage" --dry-run)"
echo "$out" | grep -q 'checksum ok: rke2.linux-amd64.tar.gz' || fail "tarball checksum not reported"
echo "$out" | grep -q 'systemctl start rke2-server.service' || fail "server start not planned"
echo "$out" | grep -q 'dry run complete' || fail "no dry run footer"
check "dry run on good stage"

out="$("$script" --dir "$stage" --type agent --no-start --dry-run)"
echo "$out" | grep -q 'systemctl enable rke2-agent.service' || fail "agent enable not planned"
echo "$out" | grep -q 'systemctl start' && fail "start planned despite --no-start"
check "agent type and --no-start"

printf 'tampered\n' >> "$stage/rke2.linux-amd64.tar.gz"
if "$script" --dir "$stage" --dry-run 2>"$work/err"; then fail "tampered tarball accepted"; fi
grep -q 'checksum mismatch' "$work/err" || fail "mismatch not reported"
check "tamper detected"

if "$script" --dir "$work/nope" --dry-run 2>/dev/null; then fail "missing dir accepted"; fi
check "missing dir rejected"

if "$script" --dir "$stage" --type bogus --dry-run 2>/dev/null; then fail "bad type accepted"; fi
check "bad type rejected"

printf '%s checks passed\n' "$pass"

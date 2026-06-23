#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${TMPDIR:-/tmp}/nix-termux-serve-release-smoke.$$

cleanup() {
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp/release"

for file in \
	install.sh \
	install.sh.sha256 \
	nix-termux-runtime.tar.gz \
	nix-termux-runtime.tar.gz.sha256 \
	nix-termux-channel-x86_64.json \
	nix-termux-bootstrap-x86_64.json; do
	printf '%s\n' "$file" >"$tmp/release/$file"
done

(cd "$tmp/release" && sha256sum \
	install.sh \
	install.sh.sha256 \
	nix-termux-runtime.tar.gz \
	nix-termux-runtime.tar.gz.sha256 \
	nix-termux-channel-x86_64.json \
	nix-termux-bootstrap-x86_64.json \
	>SHA256SUMS)

sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/check.out"
grep -qx "release directory ok: $tmp/release" "$tmp/check.out"

printf '%s\n' tampered >>"$tmp/release/install.sh"

if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted bad checksums" >&2
	exit 1
fi
grep -q 'release checksum verification failed' "$tmp/err"

#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${TMPDIR:-/tmp}/nix-termux-serve-release-smoke.$$

cleanup() {
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp/bin" "$tmp/release"
host_sh=$(command -v sh)

cat >"$tmp/bin/python3" <<EOF
#!$host_sh
printf '%s\n' "\$*" >"$tmp/python3.args"
EOF
chmod 755 "$tmp/bin/python3"

for file in \
	install.sh \
	install.sh.sha256 \
	nix-termux-runtime.tar.gz \
	nix-termux-runtime.tar.gz.sha256 \
	nix-termux-channel-x86_64.json \
	nix-termux-bootstrap-x86_64.json \
	nix-termux-bootstrap-x86_64.tar.gz \
	nix-termux-bootstrap-x86_64.registration \
	nix-termux-channel-aarch64.json \
	nix-termux-bootstrap-aarch64.json \
	nix-termux-bootstrap-aarch64.tar.gz \
	nix-termux-bootstrap-aarch64.registration; do
	printf '%s\n' "$file" >"$tmp/release/$file"
done

(cd "$tmp/release" && sha256sum \
	install.sh \
	install.sh.sha256 \
	nix-termux-runtime.tar.gz \
	nix-termux-runtime.tar.gz.sha256 \
	nix-termux-channel-x86_64.json \
	nix-termux-bootstrap-x86_64.json \
	nix-termux-bootstrap-x86_64.tar.gz \
	nix-termux-bootstrap-x86_64.registration \
	nix-termux-channel-aarch64.json \
	nix-termux-bootstrap-aarch64.json \
	nix-termux-bootstrap-aarch64.tar.gz \
	nix-termux-bootstrap-aarch64.registration \
	>SHA256SUMS)

sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/check.out"
grep -qx "release directory ok: $tmp/release" "$tmp/check.out"

rm "$tmp/release/nix-termux-bootstrap-x86_64.tar.gz"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted a missing bootstrap archive" >&2
	exit 1
fi
grep -q 'release directory missing nix-termux-bootstrap-x86_64.tar.gz' "$tmp/err"
printf '%s\n' nix-termux-bootstrap-x86_64.tar.gz >"$tmp/release/nix-termux-bootstrap-x86_64.tar.gz"

PATH="$tmp/bin:$PATH" sh "$repo_root/tools/serve-release.sh" "$tmp/release" 127.0.0.1 8765 >"$tmp/serve.out"
# shellcheck disable=SC2016
grep -q '^tmp_dir=$(mktemp -d)$' "$tmp/serve.out"
# shellcheck disable=SC2016
grep -q 'curl -L "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" -o "$tmp_dir/install.sh"' "$tmp/serve.out"
# shellcheck disable=SC2016
grep -q 'curl -L "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh.sha256" -o "$tmp_dir/install.sh.sha256"' "$tmp/serve.out"
grep -q 'sha256sum -c install.sh.sha256' "$tmp/serve.out"
# shellcheck disable=SC2016
grep -q 'sh "$tmp_dir/install.sh"' "$tmp/serve.out"
grep -qx -- "-m http.server 8765 --bind 127.0.0.1" "$tmp/python3.args"

printf '%s\n' tampered >>"$tmp/release/install.sh"

if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted bad checksums" >&2
	exit 1
fi
grep -q 'release checksum verification failed' "$tmp/err"

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

for file in install.sh install.sh.sha256 nix-termux-runtime.tar.gz nix-termux-runtime.tar.gz.sha256; do
	printf '%s\n' "$file" >"$tmp/release/$file"
done
(cd "$tmp/release" && sha256sum install.sh >install.sh.sha256)
(cd "$tmp/release" && sha256sum nix-termux-runtime.tar.gz >nix-termux-runtime.tar.gz.sha256)
runtime_sha=$(sha256sum "$tmp/release/nix-termux-runtime.tar.gz")
runtime_sha=${runtime_sha%% *}

for arch in x86_64 aarch64; do
	printf '%s\n' "nix-termux-bootstrap-$arch.tar.gz" >"$tmp/release/nix-termux-bootstrap-$arch.tar.gz"
	bootstrap_sha=$(sha256sum "$tmp/release/nix-termux-bootstrap-$arch.tar.gz")
	bootstrap_sha=${bootstrap_sha%% *}
	cat >"$tmp/release/nix-termux-channel-$arch.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "$arch",
    "nixSystem": "$arch-linux"
  },
  "runtime": {
    "url": "nix-termux-runtime.tar.gz",
    "sha256": "$runtime_sha"
  },
  "bootstrapManifest": {
    "url": "nix-termux-bootstrap-$arch.json"
  }
}
EOF
	cat >"$tmp/release/nix-termux-bootstrap-$arch.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "$arch",
    "nixSystem": "$arch-linux"
  },
  "archive": {
    "url": "nix-termux-bootstrap-$arch.tar.gz",
    "sha256": "$bootstrap_sha"
  }
}
EOF
	printf '%s\n' "nix-termux-bootstrap-$arch.registration" >"$tmp/release/nix-termux-bootstrap-$arch.registration"
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

cp "$tmp/release/nix-termux-channel-x86_64.json" "$tmp/channel-x86_64.good"
sed 's/"schemaVersion": 1/"schemaVersion": 2/' \
	"$tmp/channel-x86_64.good" >"$tmp/release/nix-termux-channel-x86_64.json"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted unsupported channel schema" >&2
	exit 1
fi
grep -q 'nix-termux-channel-x86_64.json has unsupported schemaVersion' "$tmp/err"
cp "$tmp/channel-x86_64.good" "$tmp/release/nix-termux-channel-x86_64.json"

sed '/"termuxArch": "x86_64"/d' \
	"$tmp/channel-x86_64.good" >"$tmp/release/nix-termux-channel-x86_64.json"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted channel without termuxArch" >&2
	exit 1
fi
grep -q 'nix-termux-channel-x86_64.json missing platform.termuxArch' "$tmp/err"
cp "$tmp/channel-x86_64.good" "$tmp/release/nix-termux-channel-x86_64.json"

sed 's/"termuxArch": "x86_64"/"termuxArch": "aarch64"/' \
	"$tmp/channel-x86_64.good" >"$tmp/release/nix-termux-channel-x86_64.json"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted channel architecture mismatch" >&2
	exit 1
fi
grep -q 'nix-termux-channel-x86_64.json platform.termuxArch mismatch: expected x86_64 got aarch64' "$tmp/err"
cp "$tmp/channel-x86_64.good" "$tmp/release/nix-termux-channel-x86_64.json"

cp "$tmp/release/nix-termux-bootstrap-x86_64.json" "$tmp/bootstrap-x86_64.good"
sed 's/"schemaVersion": 1/"schemaVersion": 2/' \
	"$tmp/bootstrap-x86_64.good" >"$tmp/release/nix-termux-bootstrap-x86_64.json"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted unsupported bootstrap schema" >&2
	exit 1
fi
grep -q 'nix-termux-bootstrap-x86_64.json has unsupported schemaVersion' "$tmp/err"
cp "$tmp/bootstrap-x86_64.good" "$tmp/release/nix-termux-bootstrap-x86_64.json"

sed '/"termuxArch": "x86_64"/d' \
	"$tmp/bootstrap-x86_64.good" >"$tmp/release/nix-termux-bootstrap-x86_64.json"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted bootstrap without termuxArch" >&2
	exit 1
fi
grep -q 'nix-termux-bootstrap-x86_64.json missing platform.termuxArch' "$tmp/err"
cp "$tmp/bootstrap-x86_64.good" "$tmp/release/nix-termux-bootstrap-x86_64.json"

sed 's/"termuxArch": "x86_64"/"termuxArch": "aarch64"/' \
	"$tmp/bootstrap-x86_64.good" >"$tmp/release/nix-termux-bootstrap-x86_64.json"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted bootstrap architecture mismatch" >&2
	exit 1
fi
grep -q 'nix-termux-bootstrap-x86_64.json platform.termuxArch mismatch: expected x86_64 got aarch64' "$tmp/err"
cp "$tmp/bootstrap-x86_64.good" "$tmp/release/nix-termux-bootstrap-x86_64.json"

rm "$tmp/release/nix-termux-bootstrap-x86_64.tar.gz"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted a missing bootstrap archive" >&2
	exit 1
fi
grep -q 'release directory missing nix-termux-bootstrap-x86_64.tar.gz' "$tmp/err"
printf '%s\n' nix-termux-bootstrap-x86_64.tar.gz >"$tmp/release/nix-termux-bootstrap-x86_64.tar.gz"

sed 's/nix-termux-bootstrap-x86_64.json/missing-bootstrap-x86_64.json/' \
	"$tmp/channel-x86_64.good" >"$tmp/release/nix-termux-channel-x86_64.json"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted a missing channel bootstrap reference" >&2
	exit 1
fi
grep -q 'nix-termux-channel-x86_64.json references missing bootstrap manifest: missing-bootstrap-x86_64.json' "$tmp/err"
cp "$tmp/channel-x86_64.good" "$tmp/release/nix-termux-channel-x86_64.json"

printf '%s\n' outside >"$tmp/outside-bootstrap.json"
sed 's/nix-termux-bootstrap-x86_64.json/..\/outside-bootstrap.json/' \
	"$tmp/channel-x86_64.good" >"$tmp/release/nix-termux-channel-x86_64.json"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted unsafe channel bootstrap reference" >&2
	exit 1
fi
grep -q 'nix-termux-channel-x86_64.json references unsafe bootstrap manifest URL: ../outside-bootstrap.json' "$tmp/err"
cp "$tmp/channel-x86_64.good" "$tmp/release/nix-termux-channel-x86_64.json"

sed 's/"sha256": "[0-9a-f]*"/"sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"/' \
	"$tmp/bootstrap-x86_64.good" >"$tmp/release/nix-termux-bootstrap-x86_64.json"
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted a bad bootstrap archive hash" >&2
	exit 1
fi
grep -q 'nix-termux-bootstrap-x86_64.json archive sha256 mismatch' "$tmp/err"
cp "$tmp/bootstrap-x86_64.good" "$tmp/release/nix-termux-bootstrap-x86_64.json"

cp "$tmp/release/install.sh.sha256" "$tmp/install-sh-sha256.good"
printf '%s  install.sh\n' "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" >"$tmp/release/install.sh.sha256"
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
if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted a bad installer checksum file" >&2
	exit 1
fi
grep -q 'installer checksum verification failed' "$tmp/err"
cp "$tmp/install-sh-sha256.good" "$tmp/release/install.sh.sha256"
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

if PATH="$tmp/bin:$PATH" sh "$repo_root/tools/serve-release.sh" "$tmp/release" 127.0.0.1 0 >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted port 0" >&2
	exit 1
fi
grep -q 'serve-release.sh: port must be between 1 and 65535' "$tmp/err"

if PATH="$tmp/bin:$PATH" sh "$repo_root/tools/serve-release.sh" "$tmp/release" 127.0.0.1 65536 >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted port 65536" >&2
	exit 1
fi
grep -q 'serve-release.sh: port must be between 1 and 65535' "$tmp/err"

PATH="$tmp/bin:$PATH" sh "$repo_root/tools/serve-release.sh" "$tmp/release" 127.0.0.1 8765 >"$tmp/serve.out"
# shellcheck disable=SC2016
grep -q '^tmp_dir=$(mktemp -d)$' "$tmp/serve.out"
# shellcheck disable=SC2016
grep -q 'curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" -o "$tmp_dir/install.sh"' "$tmp/serve.out"
# shellcheck disable=SC2016
grep -q 'curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh.sha256" -o "$tmp_dir/install.sh.sha256"' "$tmp/serve.out"
grep -q 'sha256sum -c install.sh.sha256' "$tmp/serve.out"
# shellcheck disable=SC2016
grep -q 'sh "$tmp_dir/install.sh"' "$tmp/serve.out"
grep -qx -- "-m http.server 8765 --bind 127.0.0.1" "$tmp/python3.args"

cp "$tmp/release/SHA256SUMS" "$tmp/sha256sums.good"
sed '1s/^[0-9a-f][0-9a-f]*/ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff/' \
	"$tmp/sha256sums.good" >"$tmp/release/SHA256SUMS"

if sh "$repo_root/tools/serve-release.sh" --check "$tmp/release" >"$tmp/out" 2>"$tmp/err"; then
	printf '%s\n' "serve-release unexpectedly accepted bad checksums" >&2
	exit 1
fi
grep -q 'release checksum verification failed' "$tmp/err"

#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${TMPDIR:-/tmp}/nix-termux-emulator-validate-smoke.$$

cleanup() {
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp/release"
touch "$tmp/termux.apk"

sh "$repo_root/tools/emulator-validate.sh" \
	--dry-run \
	--avd nix-termux-api-35 \
	--serial emulator-5556 \
	--release-dir "$tmp/release" \
	--bind-host 127.0.0.1 \
	--port 8123 \
	--termux-apk "$tmp/termux.apk" \
	--remote-path /sdcard/Download/custom-nix-termux.sh \
	--network \
	>"$tmp/out"

grep -q "serve-release.sh' '--check' '$tmp/release'" "$tmp/out"
grep -q "'emulator' '-avd' 'nix-termux-api-35' '-no-snapshot-save'" "$tmp/out"
grep -q "'adb' '-s' 'emulator-5556' 'install' '-r' '$tmp/termux.apk'" "$tmp/out"
grep -q "serve-release.sh' '$tmp/release' '127.0.0.1' '8123'" "$tmp/out"
grep -q "adb-validate.sh' '--serial' 'emulator-5556' '--remote-path' '/sdcard/Download/custom-nix-termux.sh' '--network' 'http://10.0.2.2:8123'" "$tmp/out"

sh "$repo_root/tools/emulator-validate.sh" \
	--dry-run \
	--no-start \
	--no-launch \
	--device-base-url http://example.invalid/nix-termux \
	--release-dir "$tmp/release" \
	>"$tmp/no-launch.out"
grep -q "adb-validate.sh' '--serial' 'emulator-5554' '--remote-path' '/sdcard/Download/nix-termux-validate.sh' '--no-launch' 'http://example.invalid/nix-termux'" "$tmp/no-launch.out"

if sh "$repo_root/tools/emulator-validate.sh" --port nope --dry-run >"$tmp/bad-port.out" 2>"$tmp/bad-port.err"; then
	printf '%s\n' "emulator-validate accepted non-numeric port" >&2
	exit 1
fi
grep -q '^emulator-validate.sh: --port must be numeric$' "$tmp/bad-port.err"

if sh "$repo_root/tools/emulator-validate.sh" --device-base-url file:///tmp/release --dry-run >"$tmp/bad-url.out" 2>"$tmp/bad-url.err"; then
	printf '%s\n' "emulator-validate accepted non-http device URL" >&2
	exit 1
fi
grep -q '^emulator-validate.sh: --device-base-url must start with http:// or https://$' "$tmp/bad-url.err"

if sh "$repo_root/tools/emulator-validate.sh" --remote-path relative.sh --dry-run >"$tmp/bad-remote.out" 2>"$tmp/bad-remote.err"; then
	printf '%s\n' "emulator-validate accepted relative remote path" >&2
	exit 1
fi
grep -q '^emulator-validate.sh: --remote-path must be an absolute device path$' "$tmp/bad-remote.err"

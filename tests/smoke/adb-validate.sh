#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${TMPDIR:-/tmp}/nix-termux-adb-validate-smoke.$$

cleanup() {
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp/bin"
host_sh=$(command -v sh)

cat >"$tmp/bin/adb" <<EOF
#!$host_sh
printf '%s\n' "\$*" >>"$tmp/adb.log"
if [ "\$1" = "-s" ]; then
	serial=\$2
	shift 2
	printf 'serial=%s\n' "\$serial" >>"$tmp/adb.log"
fi
case \$1 in
push)
	cp "\$2" "$tmp/pushed.sh"
	printf '%s\n' "\$3" >"$tmp/remote-path"
	;;
shell)
	exit 0
	;;
*)
	printf 'unexpected adb command: %s\n' "\$1" >&2
	exit 1
	;;
esac
EOF
chmod 755 "$tmp/bin/adb"

PATH="$tmp/bin:$PATH" \
	sh "$repo_root/tools/adb-validate.sh" \
	--serial emulator-5554 \
	--remote-path /sdcard/Download/custom-nix-termux.sh \
	--network \
	http://127.0.0.1:8000 >"$tmp/out"

grep -q '^serial=emulator-5554$' "$tmp/adb.log"
grep -qx '/sdcard/Download/custom-nix-termux.sh' "$tmp/remote-path"
grep -q "NIX_TERMUX_CHANNEL_BASE_URL='http://127.0.0.1:8000'" "$tmp/pushed.sh"
grep -q '^apt update$' "$tmp/pushed.sh"
grep -q 'apt -o Dpkg::Options::=--force-confold install -y proot curl tar xz-utils coreutils' "$tmp/pushed.sh"
# shellcheck disable=SC2016
grep -q 'curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" -o "$tmp_dir/install.sh"' "$tmp/pushed.sh"
# shellcheck disable=SC2016
grep -q 'curl -fL "$NIX_TERMUX_CHANNEL_BASE_URL/install.sh.sha256" -o "$tmp_dir/install.sh.sha256"' "$tmp/pushed.sh"
grep -q 'sha256sum -c install.sh.sha256' "$tmp/pushed.sh"
# shellcheck disable=SC2016
grep -q 'sh "$tmp_dir/install.sh"' "$tmp/pushed.sh"
grep -q 'nix-termux smoke-test --network' "$tmp/pushed.sh"
grep -q "sh '/sdcard/Download/custom-nix-termux.sh'" "$tmp/out"

PATH="$tmp/bin:$PATH" \
	sh "$repo_root/tools/adb-validate.sh" \
	--remote-path "/sdcard/Download/nix termux validate.sh" \
	--no-launch \
	http://127.0.0.1:8000 >"$tmp/quoted-path.out"
grep -q "sh '/sdcard/Download/nix termux validate.sh'" "$tmp/quoted-path.out"

if PATH="$tmp/bin:$PATH" sh "$repo_root/tools/adb-validate.sh" >"$tmp/usage.out" 2>"$tmp/usage.err"; then
	printf '%s\n' "adb-validate without base URL unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^Usage: adb-validate.sh' "$tmp/usage.err"

if PATH="$tmp/bin:$PATH" sh "$repo_root/tools/adb-validate.sh" --serial "" http://127.0.0.1:8000 >"$tmp/serial-empty.out" 2>"$tmp/serial-empty.err"; then
	printf '%s\n' "adb-validate with empty serial unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^adb-validate.sh: --serial requires a non-empty value$' "$tmp/serial-empty.err"

if PATH="$tmp/bin:$PATH" sh "$repo_root/tools/adb-validate.sh" --serial "bad serial" http://127.0.0.1:8000 >"$tmp/serial-space.out" 2>"$tmp/serial-space.err"; then
	printf '%s\n' "adb-validate with whitespace in serial unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^adb-validate.sh: --serial must not contain whitespace$' "$tmp/serial-space.err"

if PATH="$tmp/bin:$PATH" sh "$repo_root/tools/adb-validate.sh" --remote-path "" http://127.0.0.1:8000 >"$tmp/remote-path-empty.out" 2>"$tmp/remote-path-empty.err"; then
	printf '%s\n' "adb-validate with empty remote path unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^adb-validate.sh: --remote-path requires a non-empty value$' "$tmp/remote-path-empty.err"

if PATH="$tmp/bin:$PATH" sh "$repo_root/tools/adb-validate.sh" --remote-path relative/script.sh http://127.0.0.1:8000 >"$tmp/remote-path-relative.out" 2>"$tmp/remote-path-relative.err"; then
	printf '%s\n' "adb-validate with relative remote path unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^adb-validate.sh: --remote-path must be an absolute device path$' "$tmp/remote-path-relative.err"

if PATH="$tmp/bin:$PATH" sh "$repo_root/tools/adb-validate.sh" "" >"$tmp/base-url-empty.out" 2>"$tmp/base-url-empty.err"; then
	printf '%s\n' "adb-validate with empty base URL unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^adb-validate.sh: base-url must not be empty$' "$tmp/base-url-empty.err"

if PATH="$tmp/bin:$PATH" sh "$repo_root/tools/adb-validate.sh" "http://127.0.0.1:8000/bad url" >"$tmp/base-url-space.out" 2>"$tmp/base-url-space.err"; then
	printf '%s\n' "adb-validate with whitespace in base URL unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^adb-validate.sh: base-url must not contain whitespace$' "$tmp/base-url-space.err"

if PATH="$tmp/bin:$PATH" sh "$repo_root/tools/adb-validate.sh" "file:///tmp/release" >"$tmp/base-url-scheme.out" 2>"$tmp/base-url-scheme.err"; then
	printf '%s\n' "adb-validate with non-http base URL unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^adb-validate.sh: base-url must start with http:// or https://$' "$tmp/base-url-scheme.err"

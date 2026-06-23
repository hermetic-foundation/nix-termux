#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

failures=0

say() {
	printf '%s\n' "$*"
}

fail() {
	failures=$((failures + 1))
	printf 'not ok - %s\n' "$*" >&2
}

ok() {
	printf 'ok - %s\n' "$*"
}

have() {
	command -v "$1" >/dev/null 2>&1
}

check() {
	name=$1
	shift

	if "$@"; then
		ok "$name"
	else
		fail "$name"
	fi
}

check_json_bool() {
	key=$1
	file=$2

	if have jq; then
		jq -e "$key == true" "$file" >/dev/null
	else
		case $key in
		.ok)
			grep -Eq '"ok"[[:space:]]*:[[:space:]]*true' "$file"
			;;
		.*.ok)
			section=${key#.}
			section=${section%%.*}
			sed -n '/"'"$section"'"[[:space:]]*:/,/}/p' "$file" |
				grep -Eq '"ok"[[:space:]]*:[[:space:]]*true'
			;;
		*)
			return 1
			;;
		esac
	fi
}

state_dir=${NIX_TERMUX_STATE_DIR:-"$HOME/.nix-termux"}
prefix=${PREFIX:-}
tmp=${TMPDIR:-${PREFIX:-/tmp}/tmp}/nix-termux-device-smoke.$$

cleanup() {
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp"

say "nix-termux device smoke"
say "state: $state_dir"
say "prefix: ${prefix:-unset}"

check "PREFIX is set" test -n "$prefix"
check "PREFIX/bin exists" test -d "$prefix/bin"
check "nix-termux is on PATH" have nix-termux
check "proot is on PATH" have proot

for name in nix nix-shell nix-env nix-store nix-build nix-channel nix-collect-garbage nix-copy-closure nix-hash nix-instantiate nix-prefetch-url; do
	check "$name wrapper exists" test -x "$prefix/bin/$name"
done

doctor_json=$tmp/doctor.json
if nix-termux doctor --json >"$doctor_json"; then
	ok "doctor --json exits successfully"
else
	fail "doctor --json exits successfully"
fi

check "doctor reports ok" check_json_bool ".ok" "$doctor_json"
check "doctor reports Termux" check_json_bool ".termux.ok" "$doctor_json"
check "doctor reports proot" check_json_bool ".proot.ok" "$doctor_json"
check "doctor reports store" check_json_bool ".store.ok" "$doctor_json"
check "doctor reports nix" check_json_bool ".nix.ok" "$doctor_json"
check "doctor reports nix.conf" check_json_bool ".nixConf.ok" "$doctor_json"
check "doctor reports certs" check_json_bool ".certs.ok" "$doctor_json"
check "doctor reports dns" check_json_bool ".dns.ok" "$doctor_json"
check "doctor reports wrappers" check_json_bool ".wrappers.ok" "$doctor_json"
check "doctor reports activation" check_json_bool ".activation.ok" "$doctor_json"

check "nix wrapper runs" nix --version
check "nix-store wrapper runs" nix-store --version
for name in nix-shell nix-env nix-build nix-channel nix-collect-garbage nix-copy-closure nix-hash nix-instantiate nix-prefetch-url; do
	check "$name wrapper runs" "$name" --version
done
check "nix-termux exec runs nix" nix-termux exec nix --version
check "proot resolves termux user" nix-termux exec sh -c 'grep -q "^termux:" /etc/passwd && grep -q "^termux:" /etc/group'
check "proot has resolver config" nix-termux exec sh -c 'test -s /etc/resolv.conf && grep -q "^nameserver " /etc/resolv.conf'
# shellcheck disable=SC2016
check "proot provides writable /tmp" nix-termux exec sh -c 'test -d /tmp && test -w /tmp && test "$TMPDIR" = /tmp'
# shellcheck disable=SC2016
check "proot provides XDG dirs" nix-termux exec sh -c 'test "$XDG_CONFIG_HOME" = /home/termux/.config && test -d "$XDG_CONFIG_HOME" && test -w "$XDG_CONFIG_HOME" && test "$XDG_CACHE_HOME" = /home/termux/.cache && test -d "$XDG_CACHE_HOME" && test -w "$XDG_CACHE_HOME" && test "$XDG_DATA_HOME" = /home/termux/.local/share && test -d "$XDG_DATA_HOME" && test -w "$XDG_DATA_HOME" && test "$XDG_STATE_HOME" = /home/termux/.local/state && test -d "$XDG_STATE_HOME" && test -w "$XDG_STATE_HOME"'
# shellcheck disable=SC2016
check "proot uses local Nix store" sh -c 'NIX_REMOTE=daemon nix-termux exec sh -c '\''test "$NIX_REMOTE" = local'\'''
# shellcheck disable=SC2016
check "proot provides legacy NIX_PATH" nix-termux exec sh -c 'test "$NIX_PATH" = nixpkgs=flake:nixpkgs'
# shellcheck disable=SC2016
check "proot provides certificate bundle env" nix-termux exec sh -c 'test "$NIX_SSL_CERT_FILE" = /nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt && test "$SSL_CERT_FILE" = "$NIX_SSL_CERT_FILE" && test -r "$SSL_CERT_FILE"'
# shellcheck disable=SC2016
check "proot provides Nix profile env" nix-termux exec sh -c 'test "$NIX_PROFILES" = "/nix/var/nix/profiles/default /nix/var/nix/profiles/per-user/termux/profile" && test -L "$HOME/.nix-profile"'

if [ "${NIX_TERMUX_DEVICE_SMOKE_NETWORK:-0}" = "1" ]; then
	check "nix run can fetch and execute hello" nix-termux run nixpkgs#hello
else
	say "skip - nix run nixpkgs#hello (set NIX_TERMUX_DEVICE_SMOKE_NETWORK=1)"
fi

if [ "$failures" -ne 0 ]; then
	printf '%s\n' "$failures device smoke check(s) failed" >&2
	exit 1
fi

say "device smoke passed"

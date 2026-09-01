#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

die() {
	printf 'nix-termux: %s\n' "$*" >&2
	exit 1
}

[ "$#" -gt 0 ] || die "config activation requires a command"

config_flake=${NIX_TERMUX_CONFIG_FLAKE:-/home/termux/.config/nix-termux}
real_nix=${NIX_TERMUX_REAL_NIX:-/nix/var/nix/profiles/default/bin/nix}

case $config_flake in
"" | none)
	;;
*)
	case $config_flake in
	path:/*)
		config_path=${config_flake#path:}
		[ -r "$config_path/flake.nix" ] ||
			die "configuration flake not found at $config_path"
		[ -r "$config_path/flake.lock" ] ||
			die "configuration flake is not locked at $config_path"
		;;
	/* | ./* | ../*)
		[ -r "$config_flake/flake.nix" ] ||
			die "configuration flake not found at $config_flake"
		[ -r "$config_flake/flake.lock" ] ||
			die "configuration flake is not locked at $config_flake"
		;;
	esac

	[ -x "$real_nix" ] || die "Nix executable not found at $real_nix"
	if ! flake_nix_config=$(
		"$real_nix" \
			--option accept-flake-config false \
			eval \
			--raw \
			--no-write-lock-file \
			"$config_flake#nixTermux.nixConfig"
	); then
		die "failed to evaluate $config_flake#nixTermux.nixConfig"
	fi

	if [ -n "$flake_nix_config" ]; then
		if [ -n "${NIX_CONFIG:-}" ]; then
			NIX_CONFIG=$flake_nix_config'
'$NIX_CONFIG
		else
			NIX_CONFIG=$flake_nix_config
		fi
		export NIX_CONFIG
	fi
	;;
esac

export NIX_TERMUX_CONFIG_FLAKE="$config_flake"
exec "$@"

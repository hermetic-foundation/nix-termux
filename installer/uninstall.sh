#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

die() {
	printf 'uninstall.sh: %s\n' "$*" >&2
	exit 1
}

validate_state_dir() {
	case $state_dir in
	/ | . | ..)
		die "NIX_TERMUX_STATE_DIR must not be $state_dir"
		;;
	esac
}

validate_prefix() {
	case $prefix in
	/ | . | ..)
		die "PREFIX must not be $prefix"
		;;
	esac
}

[ "$#" -eq 0 ] || die "uninstall accepts no arguments"

state_dir=${NIX_TERMUX_STATE_DIR:-"$HOME/.nix-termux"}
prefix=${PREFIX:-}
wrapper_names="nix-termux nix nix-shell nix-env nix-store nix-build nix-channel nix-collect-garbage nix-copy-closure nix-hash nix-instantiate nix-prefetch-url"
managed_profile_target=/nix/var/nix/profiles/per-user/termux/profile

validate_state_dir
validate_prefix

is_managed_wrapper() {
	target=$1

	[ -f "$target" ] || return 1
	grep -q '^# nix-termux managed wrapper$' "$target"
}

restore_prefix_command() {
	name=$1
	target=$prefix/bin/$name
	backup=$state_dir/share/prefix-backup/$name

	if [ -e "$backup" ]; then
		if [ ! -e "$target" ] || is_managed_wrapper "$target"; then
			mv "$backup" "$target"
		fi
	elif is_managed_wrapper "$target"; then
		rm -f "$target"
	fi
}

if [ -n "$prefix" ] && [ -d "$prefix/bin" ]; then
	for name in $wrapper_names; do
		restore_prefix_command "$name"
	done
fi

if [ -L "$HOME/.nix-profile" ] && [ "$(readlink "$HOME/.nix-profile")" = "$managed_profile_target" ]; then
	rm -f "$HOME/.nix-profile"
fi

if [ -d "$state_dir" ]; then
	rm -rf "$state_dir"
fi

printf '%s\n' "Removed nix-termux"

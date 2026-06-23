#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

state_dir=${NIX_TERMUX_STATE_DIR:-"$HOME/.nix-termux"}
prefix=${PREFIX:-}

if [ -n "$prefix" ] && [ -d "$prefix/bin" ]; then
	rm -f "$prefix/bin/nix-termux"
	for name in nix nix-shell nix-env nix-store nix-build; do
		if [ -f "$prefix/bin/$name" ]; then
			rm -f "$prefix/bin/$name"
		fi
	done
fi

if [ -d "$state_dir" ]; then
	rm -rf "$state_dir"
fi

printf '%s\n' "Removed nix-termux"

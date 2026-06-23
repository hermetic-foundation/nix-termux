#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

extract_nix_version() {
	file=$1
	sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)";[[:space:]]*$/\1/p' "$file" | head -n 1
}

extract_runtime_version() {
	file=$1
	# shellcheck disable=SC2016
	sed -n 's/^version=${NIX_TERMUX_VERSION:-\([^}]*\)}$/\1/p' "$file" | head -n 1
}

check_version() {
	name=$1
	actual=$2

	if [ -z "$actual" ]; then
		printf 'missing version declaration: %s\n' "$name" >&2
		exit 1
	fi

	if [ "$actual" != "$expected" ]; then
		printf 'version mismatch: %s expected %s got %s\n' "$name" "$expected" "$actual" >&2
		exit 1
	fi
}

expected=$(extract_nix_version flake.nix)
check_version flake.nix "$expected"

check_version bootstrap/make-bootstrap.nix "$(extract_nix_version bootstrap/make-bootstrap.nix)"
check_version channel/make-channel.nix "$(extract_nix_version channel/make-channel.nix)"
check_version installer/make-installer.nix "$(extract_nix_version installer/make-installer.nix)"
check_version runtime/make-runtime-archive.nix "$(extract_nix_version runtime/make-runtime-archive.nix)"
check_version runtime/nix-termux.sh "$(extract_runtime_version runtime/nix-termux.sh)"

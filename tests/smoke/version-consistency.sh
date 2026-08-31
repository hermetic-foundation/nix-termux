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

extract_wrapper_names() {
	file=$1
	sed -n 's/^wrapper_names="\([^"]*\)"$/\1/p' "$file" | head -n 1
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

check_wrappers() {
	name=$1
	actual=$2

	if [ -z "$actual" ]; then
		printf 'missing wrapper_names declaration: %s\n' "$name" >&2
		exit 1
	fi

	if [ "$actual" != "$expected_wrappers" ]; then
		printf 'wrapper_names mismatch: %s\nexpected: %s\nactual:   %s\n' "$name" "$expected_wrappers" "$actual" >&2
		exit 1
	fi
}

check_spdx() {
	file=$1

	sed -n '1,3p' "$file" | grep -q 'SPDX-License-Identifier: AGPL-3.0-or-later' || {
		printf 'missing AGPL SPDX header: %s\n' "$file" >&2
		exit 1
	}
}

expected=$(extract_nix_version flake.nix)
check_version flake.nix "$expected"

check_version bootstrap/make-bootstrap.nix "$(extract_nix_version bootstrap/make-bootstrap.nix)"
check_version channel/make-channel.nix "$(extract_nix_version channel/make-channel.nix)"
check_version installer/make-installer.nix "$(extract_nix_version installer/make-installer.nix)"
check_version runtime/make-runtime-archive.nix "$(extract_nix_version runtime/make-runtime-archive.nix)"
check_version runtime/nix-termux.sh "$(extract_runtime_version runtime/nix-termux.sh)"

expected_wrappers=$(extract_wrapper_names runtime/nix-termux.sh)
check_wrappers runtime/nix-termux.sh "$expected_wrappers"
check_wrappers installer/install.sh "$(extract_wrapper_names installer/install.sh)"
check_wrappers installer/uninstall.sh "$(extract_wrapper_names installer/uninstall.sh)"

for file in \
	flake.nix \
	bootstrap/make-bootstrap.nix \
	channel/make-channel.nix \
	installer/make-installer.nix \
	release/make-release.nix \
	runtime/make-runtime-archive.nix; do
	check_spdx "$file"
done

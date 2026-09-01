#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

workflow=${1:-.github/workflows/release.yml}
nix_workflow=${2:-.github/workflows/nix-ci.yml}

[ -r "$workflow" ] || {
	printf 'workflow not readable: %s\n' "$workflow" >&2
	exit 1
}

[ -r "$nix_workflow" ] || {
	printf 'workflow not readable: %s\n' "$nix_workflow" >&2
	exit 1
}

if grep -Eq 'ubuntu-|macos-|windows-' "$workflow"; then
	printf '%s\n' "release workflow must not use hosted image runners" >&2
	exit 1
fi

grep -q 'hermetic-foundation/meta/.github/workflows/release.yml@main' "$workflow" || {
	printf '%s\n' "release workflow does not use the meta release workflow" >&2
	exit 1
}

grep -q 'hermetic-foundation/meta/.github/workflows/nix-ci.yml@main' "$nix_workflow" || {
	printf '%s\n' "Nix CI workflow does not use the meta Nix workflow" >&2
	exit 1
}

grep -q 'nix build [.][#]release-aarch64' "$workflow" || {
	printf '%s\n' "release workflow does not build the aarch64 release output" >&2
	exit 1
}

grep -q 'sha256sum -c SHA256SUMS' "$workflow" || {
	printf '%s\n' "release workflow does not verify aggregate checksums" >&2
	exit 1
}

grep -q 'sha256sum -c install.sh.sha256' "$workflow" || {
	printf '%s\n' "release workflow does not verify installer checksum file" >&2
	exit 1
}

grep -q 'tools/serve-release.sh --check dist' "$workflow" || {
	printf '%s\n' "release workflow does not run release directory validation" >&2
	exit 1
}

grep -q 'install_nix: true' "$workflow" || {
	printf '%s\n' "release workflow does not request Nix installation" >&2
	exit 1
}

grep -q 'release_files: dist/[*]' "$workflow" || {
	printf '%s\n' "release workflow does not publish the release directory" >&2
	exit 1
}

for tool in tools/adb-validate.sh tools/serve-release.sh; do
	[ -x "$tool" ] || {
		printf '%s\n' "$tool must be executable in source checkouts" >&2
		exit 1
	}
done

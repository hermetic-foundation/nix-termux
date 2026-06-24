#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

workflow=${1:-.github/workflows/ci.yml}

[ -r "$workflow" ] || {
	printf 'workflow not readable: %s\n' "$workflow" >&2
	exit 1
}

grep -q 'ubuntu-24.04-arm' "$workflow" || {
	printf '%s\n' "release workflow missing native aarch64 runner" >&2
	exit 1
}

# shellcheck disable=SC2016
grep -q 'cmp -s "$file" "dist/$name"' "$workflow" || {
	printf '%s\n' "release workflow does not reject conflicting duplicate artifacts" >&2
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

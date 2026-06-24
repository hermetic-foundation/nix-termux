#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later
set -eu

if rg -n 'curl[^\n|]*\|[[:space:]]*sh' README.md docs; then
	printf '%s\n' "documentation must not recommend curl | sh install examples" >&2
	exit 1
fi

for file in README.md docs/channel.md docs/release.md docs/bootstrap.md docs/device-validation.md; do
	grep -q 'install.sh.sha256' "$file" || {
		printf '%s\n' "$file missing install.sh.sha256 verification example" >&2
		exit 1
	}
	grep -q 'sha256sum -c install.sh.sha256' "$file" || {
		printf '%s\n' "$file missing install.sh checksum command" >&2
		exit 1
	}
done

#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

python3 tests/smoke/docs.py

if rg -n 'curl[^|]*\|[[:space:]]*sh' README.md docs; then
	printf '%s\n' "documentation must not recommend curl | sh installs" >&2
	exit 1
fi

if rg -n 'curl -L' README.md docs; then
	printf '%s\n' "installer downloads must use fail-fast curl -fL" >&2
	exit 1
fi

if find docs -maxdepth 1 -type f -name '*.md' | grep -q .; then
	printf '%s\n' "Markdown documentation must be separated into docs/user or docs/dev" >&2
	exit 1
fi

for file in \
	README.md \
	CONTRIBUTING.md \
	docs/user/README.md \
	docs/user/configuration.md \
	docs/user/install.md \
	docs/user/usage.md \
	docs/user/limitations.md \
	docs/user/troubleshooting.md \
	docs/dev/README.md \
	docs/dev/architecture.md \
	docs/dev/configuration.md \
	docs/dev/bootstrap.md \
	docs/dev/channel.md \
	docs/dev/doctor.md \
	docs/dev/device-validation.md \
	docs/dev/release.md \
	docs/dev/testing.md; do
	test -r "$file" || {
		printf 'missing documentation file: %s\n' "$file" >&2
		exit 1
	}
done

canonical=https://github.com/hermetic-foundation/nix-termux/releases/latest/download
for file in installer/install.sh README.md docs/user/install.md docs/dev/channel.md docs/dev/release.md; do
	grep -q "$canonical" "$file" || {
		printf '%s missing canonical release URL\n' "$file" >&2
		exit 1
	}
done

for term in install.sh.sha256 'sha256sum -c install.sh.sha256'; do
	grep -q "$term" docs/user/install.md || {
		printf 'user installation guide missing verified install term: %s\n' "$term" >&2
		exit 1
	}
done

for path in root/etc/hosts root/etc/hostname root/etc/nsswitch.conf; do
	grep -q "$path" docs/dev/bootstrap.md || {
		printf 'bootstrap contract missing path: %s\n' "$path" >&2
		exit 1
	}
done

for term in nix-termux-runtime.tar.gz.sha256 SHA256SUMS 'registration sidecar'; do
	grep -q "$term" docs/dev/release.md || {
		printf 'release guide missing validation term: %s\n' "$term" >&2
		exit 1
	}
done

grep -q 'release-aarch64' docs/dev/device-validation.md
grep -q 'nix-termux smoke-test --network' docs/dev/device-validation.md
grep -q 'docs/dev/' CONTRIBUTING.md

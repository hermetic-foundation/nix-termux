#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later
set -eu

if rg -n 'curl[^\n|]*\|[[:space:]]*sh' README.md docs; then
	printf '%s\n' "documentation must not recommend curl | sh install examples" >&2
	exit 1
fi
if rg -n 'curl -L' README.md docs; then
	printf '%s\n' "documentation installer downloads must use curl -fL" >&2
	exit 1
fi

for file in README.md docs/channel.md docs/release.md docs/bootstrap.md docs/device-validation.md; do
	grep -q 'install.sh.sha256' "$file" || {
		printf '%s\n' "$file missing install.sh.sha256 verification example" >&2
		exit 1
	}
	grep -q 'curl -fL .*install.sh"' "$file" || {
		printf '%s\n' "$file missing fail-fast install.sh download" >&2
		exit 1
	}
	grep -q 'curl -fL .*install.sh.sha256"' "$file" || {
		printf '%s\n' "$file missing fail-fast install.sh.sha256 download" >&2
		exit 1
	}
	grep -q 'sha256sum -c install.sh.sha256' "$file" || {
		printf '%s\n' "$file missing install.sh checksum command" >&2
		exit 1
	}
done

for path in root/etc/hosts root/etc/hostname root/etc/nsswitch.conf; do
	grep -q "$path" docs/bootstrap.md || {
		printf '%s\n' "docs/bootstrap.md missing bootstrap contract path: $path" >&2
		exit 1
	}
done

grep -q 'nix-termux-runtime.tar.gz.sha256' docs/release.md || {
	printf '%s\n' "docs/release.md missing runtime sidecar checksum validation" >&2
	exit 1
}
grep -q 'SHA256SUMS' docs/release.md || {
	printf '%s\n' "docs/release.md missing aggregate release checksum validation" >&2
	exit 1
}
grep -q 'must name their exact targets' docs/release.md || {
	printf '%s\n' "docs/release.md missing exact sidecar target validation" >&2
	exit 1
}
grep -q 'bootstrap .*registration.* sidecar' docs/release.md || {
	printf '%s\n' "docs/release.md missing bootstrap registration sidecar validation" >&2
	exit 1
}
for file in README.md docs/release.md docs/device-validation.md; do
	grep -q 'release-aarch64' "$file" || {
		printf '%s\n' "$file missing the physical-device release output" >&2
		exit 1
	}
done
grep -q 'nix-termux-runtime.tar.gz.sha256' docs/device-validation.md || {
	printf '%s\n' "docs/device-validation.md missing runtime sidecar validation" >&2
	exit 1
}
grep -q 'registration sidecars' docs/device-validation.md || {
	printf '%s\n' "docs/device-validation.md missing bootstrap registration validation" >&2
	exit 1
}

#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

artifact=${1:?usage: runtime-archive.sh <artifact-dir>}
archive=$artifact/nix-termux-runtime.tar.gz
checksum=$artifact/nix-termux-runtime.tar.gz.sha256

[ -f "$archive" ] || {
	printf '%s\n' "missing runtime archive" >&2
	exit 1
}
[ -f "$checksum" ] || {
	printf '%s\n' "missing runtime archive checksum" >&2
	exit 1
}

listing=${TMPDIR:-/tmp}/nix-termux-runtime-listing.$$
trap 'rm -f "$listing"' EXIT INT TERM

tar -tzf "$archive" >"$listing"

grep -qx './bin/nix-termux' "$listing"
grep -qx './installer/install.sh' "$listing"
grep -qx './installer/uninstall.sh' "$listing"
grep -qx './runtime/nix-termux.sh' "$listing"
grep -qx './tests/termux/device-smoke.sh' "$listing"
grep -qx './LICENSE' "$listing"
grep -qx './README.md' "$listing"
grep -qx './docs/architecture.md' "$listing"
grep -qx './docs/bootstrap.md' "$listing"
grep -qx './docs/channel.md' "$listing"
grep -qx './docs/device-validation.md' "$listing"
grep -qx './docs/doctor.md' "$listing"
grep -qx './docs/release.md' "$listing"
grep -qx './bootstrap/example-manifest.json' "$listing"
grep -qx './bootstrap/manifest.schema.json' "$listing"

(cd "$artifact" && sha256sum -c nix-termux-runtime.tar.gz.sha256)

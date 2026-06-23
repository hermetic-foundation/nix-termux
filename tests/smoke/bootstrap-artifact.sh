#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

artifact=${1:?usage: bootstrap-artifact.sh <artifact-dir>}

manifest=$(find "$artifact" -name 'nix-termux-bootstrap-*.json' | head -n 1)
archive=$(find "$artifact" -name 'nix-termux-bootstrap-*.tar.gz' | head -n 1)
registration=$(find "$artifact" -name 'nix-termux-bootstrap-*.registration' | head -n 1)

[ -n "$manifest" ] || {
	printf '%s\n' "missing bootstrap manifest" >&2
	exit 1
}
[ -n "$archive" ] || {
	printf '%s\n' "missing bootstrap archive" >&2
	exit 1
}
[ -n "$registration" ] || {
	printf '%s\n' "missing bootstrap registration" >&2
	exit 1
}

sha=$(sha256sum "$archive" | awk '{print $1}')
grep -q "\"sha256\": \"$sha\"" "$manifest"
grep -q '"schemaVersion": 1' "$manifest"
grep -q '"storeDir": "nix"' "$manifest"
grep -q '"rootDir": "root"' "$manifest"
grep -q '"nixBin": "nix/var/nix/profiles/default/bin/nix"' "$manifest"
grep -q '"registration": "nix-termux/bootstrap.registration"' "$manifest"

tar -tzf "$archive" | grep -qx './nix/var/nix/profiles/default/bin/nix'
tar -tzf "$archive" | grep -qx './nix/var/nix/profiles/default/bin/bash'
tar -tzf "$archive" | grep -qx './nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt'
tar -tzf "$archive" | grep -qx './root/usr/bin/env'
tar -tzf "$archive" | grep -qx './root/bin/sh'
tar -tzf "$archive" | grep -qx './nix-termux/bootstrap.registration'

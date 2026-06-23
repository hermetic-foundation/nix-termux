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

listing=${TMPDIR:-/tmp}/nix-termux-bootstrap-listing.$$
trap 'rm -f "$listing"' EXIT INT TERM
tar -tzf "$archive" >"$listing"

grep -qx './nix/var/nix/profiles/default/bin/nix' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/bash' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/nix-build' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/nix-channel' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/nix-collect-garbage' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/nix-copy-closure' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/nix-env' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/nix-hash' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/nix-instantiate' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/nix-prefetch-url' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/nix-shell' "$listing"
grep -qx './nix/var/nix/profiles/default/bin/nix-store' "$listing"
grep -qx './nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt' "$listing"
grep -qx './nix/var/log/nix/drvs/' "$listing"
grep -qx './nix/var/nix/db/' "$listing"
grep -qx './nix/var/nix/gcroots/auto/' "$listing"
grep -qx './nix/var/nix/profiles/per-user/root/' "$listing"
grep -qx './nix/var/nix/profiles/per-user/termux/' "$listing"
grep -qx './nix/var/nix/temproots/' "$listing"
grep -qx './root/home/' "$listing"
grep -qx './root/root/' "$listing"
grep -qx './root/tmp/' "$listing"
grep -qx './root/usr/bin/env' "$listing"
grep -qx './root/bin/sh' "$listing"
grep -qx './root/etc/passwd' "$listing"
grep -qx './root/etc/group' "$listing"
grep -qx './root/etc/nsswitch.conf' "$listing"
grep -qx './root/etc/hosts' "$listing"
grep -qx './root/etc/hostname' "$listing"
grep -qx './root/etc/nix/nix.conf' "$listing"
grep -qx './nix-termux/bootstrap.registration' "$listing"

extract_dir=${TMPDIR:-/tmp}/nix-termux-bootstrap-extract.$$
rm -rf "$extract_dir"
mkdir -p "$extract_dir"
trap 'rm -f "$listing"; rm -rf "$extract_dir"' EXIT INT TERM
tar -xzf "$archive" -C "$extract_dir" \
	./root/etc/passwd \
	./root/etc/group \
	./root/etc/nsswitch.conf \
	./root/etc/hosts \
	./root/etc/hostname
grep -qx 'termux:x:1000:1000:termux:/home/termux:/bin/sh' "$extract_dir/root/etc/passwd"
grep -qx 'termux:x:1000:' "$extract_dir/root/etc/group"
grep -qx 'hosts: files dns' "$extract_dir/root/etc/nsswitch.conf"
grep -qx '127.0.0.1 localhost' "$extract_dir/root/etc/hosts"
grep -qx 'nix-termux' "$extract_dir/root/etc/hostname"

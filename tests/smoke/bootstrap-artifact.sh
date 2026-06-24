#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

artifact=${1:?usage: bootstrap-artifact.sh <artifact-dir>}

exactly_one() {
	pattern=$1
	label=$2
	count=$(find "$artifact" -type f -name "$pattern" | wc -l)
	[ "$count" -eq 1 ] || {
		printf 'expected exactly one %s, found %s\n' "$label" "$count" >&2
		exit 1
	}
	find "$artifact" -type f -name "$pattern" | head -n 1
}

manifest=$(exactly_one 'nix-termux-bootstrap-*.json' 'bootstrap manifest')
archive=$(exactly_one 'nix-termux-bootstrap-*.tar.gz' 'bootstrap archive')
registration=$(exactly_one 'nix-termux-bootstrap-*.registration' 'bootstrap registration')

manifest_name=$(basename "$manifest")
manifest_arch=${manifest_name#nix-termux-bootstrap-}
manifest_arch=${manifest_arch%.json}
case $manifest_arch in
aarch64) expected_system=aarch64-linux ;;
arm) expected_system=armv7l-linux ;;
i686) expected_system=i686-linux ;;
x86_64) expected_system=x86_64-linux ;;
*)
	printf 'unsupported bootstrap architecture: %s\n' "$manifest_arch" >&2
	exit 1
	;;
esac

sha=$(sha256sum "$archive" | awk '{print $1}')
jq -e \
	--arg sha "$sha" \
	--arg manifest_arch "$manifest_arch" \
	--arg expected_system "$expected_system" \
	'
  .schemaVersion == 1
  and .platform.termuxArch == $manifest_arch
  and .platform.nixSystem == $expected_system
  and .archive.sha256 == $sha
  and .layout.storeDir == "nix"
  and .layout.rootDir == "root"
  and .layout.nixBin == "nix/var/nix/profiles/default/bin/nix"
  and .layout.registration == "nix-termux/bootstrap.registration"
' "$manifest" >/dev/null

listing=${TMPDIR:-/tmp}/nix-termux-bootstrap-listing.$$
trap 'rm -f "$listing" "$listing.modes"' EXIT INT TERM
tar -tzf "$archive" >"$listing"
tar -tvzf "$archive" >"$listing.modes"
if grep -q ' link to ' "$listing.modes"; then
	printf '%s\n' "bootstrap archive must not contain hard links" >&2
	exit 1
fi

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
grep -qx './nix/var/nix/profiles/default/bin/grep' "$listing"
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
trap 'rm -f "$listing" "$listing.modes"; rm -rf "$extract_dir"' EXIT INT TERM
tar -xzf "$archive" -C "$extract_dir" \
	./nix-termux/bootstrap.registration \
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
archive_registration_sha=$(sha256sum "$extract_dir/nix-termux/bootstrap.registration" | awk '{print $1}')
sidecar_registration_sha=$(sha256sum "$registration" | awk '{print $1}')
[ "$archive_registration_sha" = "$sidecar_registration_sha" ] || {
	printf '%s\n' "bootstrap registration sidecar does not match archive registration" >&2
	exit 1
}

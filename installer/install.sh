#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

die() {
	printf 'install.sh: %s\n' "$*" >&2
	exit 1
}

have() {
	command -v "$1" >/dev/null 2>&1
}

state_dir=${NIX_TERMUX_STATE_DIR:-"$HOME/.nix-termux"}
prefix=${PREFIX:-}
bootstrap_manifest_url=${NIX_TERMUX_BOOTSTRAP_MANIFEST_URL:-}
bootstrap_url=${NIX_TERMUX_BOOTSTRAP_URL:-}
bootstrap_sha256=${NIX_TERMUX_BOOTSTRAP_SHA256:-}

[ -n "$prefix" ] || die "PREFIX is not set; run this from stock Termux"
[ -d "$prefix/bin" ] || die "Termux prefix bin directory not found: $prefix/bin"

for command in mkdir chmod cp rm; do
	have "$command" || die "required command missing: $command"
done

if ! have proot; then
	die "proot is required; install it with: pkg install proot"
fi

fetch_url() {
	url=$1
	output=$2

	case $url in
	file://*)
		cp "${url#file://}" "$output"
		;;
	*)
		have curl || die "curl is required to fetch $url"
		curl -L "$url" -o "$output"
		;;
	esac
}

json_string_value() {
	key=$1
	file=$2

	sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1
}

load_manifest() {
	manifest=$1

	grep -Eq '"schemaVersion"[[:space:]]*:[[:space:]]*1([,[:space:]}]|$)' "$manifest" ||
		die "unsupported bootstrap manifest schemaVersion"
	grep -Eq '"storeDir"[[:space:]]*:[[:space:]]*"nix"' "$manifest" ||
		die "unsupported bootstrap manifest storeDir"
	grep -Eq '"rootDir"[[:space:]]*:[[:space:]]*"root"' "$manifest" ||
		die "unsupported bootstrap manifest rootDir"
	grep -Eq '"nixBin"[[:space:]]*:[[:space:]]*"nix/var/nix/profiles/default/bin/nix"' "$manifest" ||
		die "unsupported bootstrap manifest nixBin"

	manifest_url=$(json_string_value url "$manifest")
	manifest_sha256=$(json_string_value sha256 "$manifest")
	[ -n "$manifest_url" ] || die "bootstrap manifest missing archive.url"
	[ -n "$manifest_sha256" ] || die "bootstrap manifest missing archive.sha256"

	bootstrap_url=${bootstrap_url:-"$manifest_url"}
	bootstrap_sha256=${bootstrap_sha256:-"$manifest_sha256"}
}

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

if [ -f "$source_root/bin/nix-termux" ]; then
	source_bin=$source_root/bin/nix-termux
	source_install=$source_root/installer/install.sh
	source_runtime=$source_root/runtime/nix-termux.sh
	source_uninstall=$source_root/installer/uninstall.sh
else
	source_bin=$state_dir/bin/nix-termux
	source_install=$state_dir/share/installer/install.sh
	source_runtime=$state_dir/runtime/nix-termux.sh
	source_uninstall=$state_dir/share/installer/uninstall.sh
fi

install_file() {
	source=$1
	target=$2

	[ -r "$source" ] || die "source file not found: $source"
	if [ "$source" != "$target" ]; then
		cp "$source" "$target"
	fi
}

mkdir -p "$state_dir/bin" "$state_dir/etc" "$state_dir/runtime" "$state_dir/share/installer" "$state_dir/root/usr/bin" "$state_dir/nix"

if [ -n "$bootstrap_manifest_url" ]; then
	manifest=$state_dir/bootstrap-manifest.json
	fetch_url "$bootstrap_manifest_url" "$manifest"
	load_manifest "$manifest"
fi

install_file "$source_bin" "$state_dir/bin/nix-termux"
install_file "$source_install" "$state_dir/share/installer/install.sh"
install_file "$source_runtime" "$state_dir/runtime/nix-termux.sh"
install_file "$source_uninstall" "$state_dir/share/installer/uninstall.sh"
chmod 755 "$state_dir/bin/nix-termux" "$state_dir/share/installer/install.sh" "$state_dir/runtime/nix-termux.sh" "$state_dir/share/installer/uninstall.sh"

cat >"$prefix/bin/nix-termux" <<EOF
#!$prefix/bin/sh
export NIX_TERMUX_LIBEXEC='$state_dir/runtime'
exec sh '$state_dir/bin/nix-termux' "\$@"
EOF
chmod 755 "$prefix/bin/nix-termux"

for name in nix nix-shell nix-env nix-store nix-build; do
	cat >"$prefix/bin/$name" <<EOF
#!$prefix/bin/sh
exec '$prefix/bin/nix-termux' exec $name "\$@"
EOF
	chmod 755 "$prefix/bin/$name"
done

if [ -n "$bootstrap_url" ]; then
	have tar || die "tar is required to unpack NIX_TERMUX_BOOTSTRAP_URL"

	archive=$state_dir/bootstrap.tar
	fetch_url "$bootstrap_url" "$archive"

	if [ -n "$bootstrap_sha256" ]; then
		have sha256sum || die "sha256sum is required when NIX_TERMUX_BOOTSTRAP_SHA256 is set"
		actual=$(sha256sum "$archive" | awk '{print $1}')
		[ "$actual" = "$bootstrap_sha256" ] || die "bootstrap sha256 mismatch: expected $bootstrap_sha256 got $actual"
	fi

	tar -xf "$archive" -C "$state_dir"
	rm -f "$archive"
fi

{
	printf 'bootstrap_manifest_url=%s\n' "$bootstrap_manifest_url"
	printf 'bootstrap_url=%s\n' "$bootstrap_url"
	printf 'bootstrap_sha256=%s\n' "$bootstrap_sha256"
} >"$state_dir/etc/nix-termux.conf"

printf '%s\n' "Installed nix-termux to $state_dir"
printf '%s\n' "Run: nix-termux doctor"

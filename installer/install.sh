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

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

mkdir -p "$state_dir/bin" "$state_dir/runtime" "$state_dir/share/installer" "$state_dir/root/usr/bin" "$state_dir/nix"

cp "$repo_root/bin/nix-termux" "$state_dir/bin/nix-termux"
cp "$repo_root/runtime/nix-termux.sh" "$state_dir/runtime/nix-termux.sh"
cp "$repo_root/installer/uninstall.sh" "$state_dir/share/installer/uninstall.sh"
chmod 755 "$state_dir/bin/nix-termux" "$state_dir/runtime/nix-termux.sh" "$state_dir/share/installer/uninstall.sh"

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
	have curl || die "curl is required to fetch NIX_TERMUX_BOOTSTRAP_URL"
	have tar || die "tar is required to unpack NIX_TERMUX_BOOTSTRAP_URL"

	archive=$state_dir/bootstrap.tar
	curl -L "$bootstrap_url" -o "$archive"

	if [ -n "$bootstrap_sha256" ]; then
		have sha256sum || die "sha256sum is required when NIX_TERMUX_BOOTSTRAP_SHA256 is set"
		actual=$(sha256sum "$archive" | awk '{print $1}')
		[ "$actual" = "$bootstrap_sha256" ] || die "bootstrap sha256 mismatch: expected $bootstrap_sha256 got $actual"
	fi

	tar -xf "$archive" -C "$state_dir"
	rm -f "$archive"
fi

printf '%s\n' "Installed nix-termux to $state_dir"
printf '%s\n' "Run: nix-termux doctor"

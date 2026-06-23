#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${TMPDIR:-/tmp}/nix-termux-smoke.$$

cleanup() {
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp/home" "$tmp/prefix/bin" "$tmp/fake-bin" "$tmp/bootstrap"
host_sh=$(command -v sh)
cp "$host_sh" "$tmp/prefix/bin/sh"

cat >"$tmp/fake-bin/proot" <<EOF
#!$host_sh
while [ "\$#" -gt 0 ]; do
	case "\$1" in
		--link2symlink | -0)
			shift
			;;
		-r | -b | -w)
			shift 2
			;;
		*)
			break
			;;
	esac
done
if [ "\$1" = "/usr/bin/env" ]; then
	shift
fi
while [ "\$#" -gt 0 ]; do
	case "\$1" in
		*=*)
			shift
			;;
		*)
			break
			;;
	esac
done
if [ "\$1" = "nix" ]; then
	shift
	exec "\$NIX_TERMUX_STATE_DIR/nix/var/nix/profiles/default/bin/nix" "\$@"
fi
exec "\$@"
EOF
chmod 755 "$tmp/fake-bin/proot"

mkdir -p \
	"$tmp/bootstrap/nix/store" \
	"$tmp/bootstrap/nix/var/nix/profiles/default/bin" \
	"$tmp/bootstrap/root/usr/bin"

cat >"$tmp/bootstrap/nix/var/nix/profiles/default/bin/nix" <<EOF
#!$host_sh
printf 'fake nix'
for arg in "\$@"; do
	printf ' %s' "\$arg"
done
printf '\n'
EOF
chmod 755 "$tmp/bootstrap/nix/var/nix/profiles/default/bin/nix"
cp "$(command -v env)" "$tmp/bootstrap/root/usr/bin/env"

(cd "$tmp/bootstrap" && tar -cf "$tmp/bootstrap.tar" .)
sha=$(sha256sum "$tmp/bootstrap.tar" | awk '{print $1}')

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	NIX_TERMUX_BOOTSTRAP_URL="file://$tmp/bootstrap.tar" \
	NIX_TERMUX_BOOTSTRAP_SHA256="$sha" \
	sh "$repo_root/installer/install.sh"

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" doctor

output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" run nixpkgs#hello
)

[ "$output" = "fake nix run nixpkgs#hello" ] || {
	printf 'unexpected output: %s\n' "$output" >&2
	exit 1
}

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" uninstall

[ ! -e "$tmp/prefix/bin/nix-termux" ]
[ ! -d "$tmp/home/.nix-termux" ]

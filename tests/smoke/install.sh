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
if [ "\$1" = "nix" ] || [ "\$1" = "nix-store" ]; then
	command=\$1
	shift
	exec "\$NIX_TERMUX_STATE_DIR/nix/var/nix/profiles/default/bin/\$command" "\$@"
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
cat >"$tmp/bootstrap/nix/var/nix/profiles/default/bin/nix-store" <<EOF
#!$host_sh
if [ "\$1" = "--load-db" ]; then
	cat >"\$NIX_TERMUX_STATE_DIR/load-db.input"
	printf '%s\n' "loaded db"
	exit 0
fi
printf 'fake nix-store'
for arg in "\$@"; do
	printf ' %s' "\$arg"
done
printf '\n'
EOF
chmod 755 "$tmp/bootstrap/nix/var/nix/profiles/default/bin/nix-store"
cp "$(command -v env)" "$tmp/bootstrap/root/usr/bin/env"
mkdir -p "$tmp/bootstrap/nix-termux"
printf '%s\n' "fake registration" >"$tmp/bootstrap/nix-termux/bootstrap.registration"

(cd "$tmp/bootstrap" && tar -cf "$tmp/bootstrap.tar" .)
sha=$(sha256sum "$tmp/bootstrap.tar" | awk '{print $1}')
cat >"$tmp/bootstrap-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "archive": {
    "url": "bootstrap.tar",
    "sha256": "$sha"
  },
  "layout": {
    "storeDir": "nix",
    "rootDir": "root",
    "nixBin": "nix/var/nix/profiles/default/bin/nix",
    "registration": "nix-termux/bootstrap.registration"
  }
}
EOF

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-manifest.json" \
	sh "$repo_root/installer/install.sh"

grep -q '^fake registration$' "$tmp/home/.nix-termux/load-db.input"

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" doctor

grep -q '^bootstrap_manifest_url=file://.*/bootstrap-manifest.json$' "$tmp/home/.nix-termux/etc/nix-termux.conf"

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" upgrade-bootstrap

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

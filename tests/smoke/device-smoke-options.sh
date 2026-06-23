#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${TMPDIR:-/tmp}/nix-termux-device-options.$$

cleanup() {
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp/bin" "$tmp/core-bin" "$tmp/prefix/bin"
host_sh=$(command -v sh)
host_cat=$(command -v cat)
host_grep=$(command -v grep)
host_head=$(command -v head)
host_mkdir=$(command -v mkdir)
host_rm=$(command -v rm)
host_sed=$(command -v sed)

ln -s "$host_cat" "$tmp/core-bin/cat"
ln -s "$host_grep" "$tmp/core-bin/grep"
ln -s "$host_head" "$tmp/core-bin/head"
ln -s "$host_mkdir" "$tmp/core-bin/mkdir"
ln -s "$host_rm" "$tmp/core-bin/rm"
ln -s "$host_sed" "$tmp/core-bin/sed"
ln -s "$host_sh" "$tmp/core-bin/sh"

cat >"$tmp/bin/proot" <<'EOF'
#!HOST_SH
exit 0
EOF
sed "s|^#!HOST_SH|#!$host_sh|" "$tmp/bin/proot" >"$tmp/bin/proot.tmp"
mv "$tmp/bin/proot.tmp" "$tmp/bin/proot"
chmod 755 "$tmp/bin/proot"

cat >"$tmp/bin/nix-termux" <<EOF
#!$host_sh
case \$1 in
version)
	printf '%s\n' '0.2.3+smoke'
	;;
doctor)
	cat <<'JSON'
{
  "schemaVersion": 1,
  "runtimeVersion": "0.2.3+smoke",
  "installedRuntimeVersion": "0.2.3+smoke",
  "ok": true,
  "termux": { "ok": true },
  "proot": { "ok": true },
  "store": { "ok": true },
  "nix": { "ok": true },
  "userProfile": { "ok": true },
  "nixConf": { "ok": true },
  "certs": { "ok": true },
  "dns": { "ok": true },
  "wrappers": { "ok": true },
  "activation": { "ok": true }
}
JSON
	;;
exec)
	shift
	case \$1 in
	nix)
		printf '%s\n' 'fake nix'
		;;
	sh)
		exit 0
		;;
	*)
		printf 'unexpected exec command: %s\n' "\$1" >&2
		exit 1
		;;
	esac
	;;
run)
	shift
	printf '%s\n' "\$*" >"$tmp/network-run"
	;;
*)
	printf 'unexpected nix-termux command: %s\n' "\$1" >&2
	exit 1
	;;
esac
EOF
chmod 755 "$tmp/bin/nix-termux"

for name in nix nix-shell nix-env nix-store nix-build nix-channel nix-collect-garbage nix-copy-closure nix-hash nix-instantiate nix-prefetch-url; do
	cat >"$tmp/prefix/bin/$name" <<EOF
#!$host_sh
printf '%s\n' 'fake $name'
EOF
	chmod 755 "$tmp/prefix/bin/$name"
done

run_smoke() {
	PATH="$tmp/bin:$tmp/prefix/bin:$tmp/core-bin" \
		PREFIX="$tmp/prefix" \
		HOME="$tmp/home" \
		sh "$repo_root/tests/termux/device-smoke.sh" "$@"
}

run_smoke >"$tmp/no-network.out"
grep -q 'skip - nix run nixpkgs#hello' "$tmp/no-network.out"
test ! -e "$tmp/network-run"

run_smoke --network >"$tmp/network.out"
grep -q 'device smoke passed' "$tmp/network.out"
grep -qx 'nixpkgs#hello' "$tmp/network-run"

rm -f "$tmp/network-run"
NIX_TERMUX_DEVICE_SMOKE_NETWORK=1 run_smoke --no-network >"$tmp/no-network-override.out"
grep -q 'skip - nix run nixpkgs#hello' "$tmp/no-network-override.out"
test ! -e "$tmp/network-run"

if run_smoke --unknown >"$tmp/unknown.out" 2>"$tmp/unknown.err"; then
	printf '%s\n' "unknown device smoke option unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^Usage: device-smoke.sh' "$tmp/unknown.err"

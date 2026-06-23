#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${TMPDIR:-/tmp}/nix-termux-smoke.$$

cleanup() {
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp/home" "$tmp/prefix/bin" "$tmp/prefix/etc" "$tmp/fake-bin" "$tmp/bootstrap" "$tmp/runtime-source" "$tmp/standalone"
host_sh=$(command -v sh)
cp "$host_sh" "$tmp/prefix/bin/sh"
cat >"$tmp/prefix/bin/nix-hash" <<EOF
#!$host_sh
printf '%s\n' original nix-hash
EOF
chmod 755 "$tmp/prefix/bin/nix-hash"
printf '%s\n' "nameserver 192.0.2.53" >"$tmp/prefix/etc/resolv.conf"
cp "$repo_root/installer/install.sh" "$tmp/standalone/install.sh"
mkdir -p "$tmp/runtime-source/bin" "$tmp/runtime-source/installer" "$tmp/runtime-source/runtime" "$tmp/runtime-source/tests/termux"
cp "$repo_root/bin/nix-termux" "$tmp/runtime-source/bin/nix-termux"
cp "$repo_root/installer/install.sh" "$tmp/runtime-source/installer/install.sh"
cp "$repo_root/installer/uninstall.sh" "$tmp/runtime-source/installer/uninstall.sh"
cp "$repo_root/runtime/nix-termux.sh" "$tmp/runtime-source/runtime/nix-termux.sh"
cp "$repo_root/tests/termux/device-smoke.sh" "$tmp/runtime-source/tests/termux/device-smoke.sh"
(cd "$tmp/runtime-source" && tar -czf "$tmp/runtime.tar.gz" .)
runtime_sha=$(sha256sum "$tmp/runtime.tar.gz" | awk '{print $1}')

cat >"$tmp/fake-bin/proot" <<EOF
#!$host_sh
printf '%s\n' "\$@" >"\$NIX_TERMUX_STATE_DIR/proot.args"
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
	"$tmp/bootstrap/nix/var/nix/profiles/default/etc/ssl/certs" \
	"$tmp/bootstrap/root/etc/nix" \
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
printf '%s\n' "experimental-features = nix-command flakes" >"$tmp/bootstrap/root/etc/nix/nix.conf"
printf '%s\n' "fake cert bundle" >"$tmp/bootstrap/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
mkdir -p "$tmp/bootstrap/nix-termux"
printf '%s\n' "fake registration" >"$tmp/bootstrap/nix-termux/bootstrap.registration"

(cd "$tmp/bootstrap" && tar -czf "$tmp/bootstrap.tar.gz" .)
sha=$(sha256sum "$tmp/bootstrap.tar.gz" | awk '{print $1}')
cat >"$tmp/bootstrap-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "archive": {
    "url": "bootstrap.tar.gz",
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
cat >"$tmp/channel.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "runtime": {
    "url": "runtime.tar.gz",
    "sha256": "$runtime_sha"
  },
  "bootstrapManifest": {
    "url": "bootstrap-manifest.json"
  }
}
EOF
cp "$tmp/channel.json" "$tmp/nix-termux-channel-x86_64.json"
cat >"$tmp/fake-bin/pkg" <<'EOF'
#!/usr/bin/env sh
if [ "$1" = "--print-architecture" ]; then
	printf '%s\n' x86_64
	exit 0
fi
exit 1
EOF
chmod 755 "$tmp/fake-bin/pkg"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/mismatch-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/mismatch-home/.nix-termux" \
	NIX_TERMUX_ARCH=aarch64 \
	NIX_TERMUX_CHANNEL_URL="file://$tmp/channel.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/channel-mismatch.err"; then
	printf '%s\n' "wrong-arch channel install unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'channel manifest architecture mismatch: expected aarch64 got x86_64' "$tmp/channel-mismatch.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/mismatch-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/mismatch-home/.nix-termux" \
	NIX_TERMUX_ARCH=aarch64 \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-manifest.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-mismatch.err"; then
	printf '%s\n' "wrong-arch bootstrap install unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap manifest architecture mismatch: expected aarch64 got x86_64' "$tmp/bootstrap-mismatch.err"

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	NIX_TERMUX_CHANNEL_BASE_URL="file://$tmp" \
	sh "$tmp/standalone/install.sh"

grep -q '^fake registration$' "$tmp/home/.nix-termux/load-db.input"
grep -q '^registration_loaded=yes$' "$tmp/home/.nix-termux/etc/bootstrap-activation.conf"
grep -q "^bootstrap_sha256=$sha$" "$tmp/home/.nix-termux/etc/bootstrap-activation.conf"
grep -q '^termux_arch=x86_64$' "$tmp/home/.nix-termux/etc/nix-termux.conf"
grep -q '^channel_url=file://.*/nix-termux-channel-x86_64.json$' "$tmp/home/.nix-termux/etc/nix-termux.conf"
grep -q "^runtime_archive_sha256=$runtime_sha$" "$tmp/home/.nix-termux/etc/nix-termux.conf"
test -x "$tmp/home/.nix-termux/share/tests/device-smoke.sh"
test -d "$tmp/home/.nix-termux/root/home"
test -d "$tmp/home/.nix-termux/root/root"
test -d "$tmp/home/.nix-termux/root/tmp"
test -d "$tmp/home/.nix-termux/tmp"
test -d "$tmp/home/.nix-termux/nix/var/nix/profiles/per-user/root"
test -d "$tmp/home/.nix-termux/nix/var/nix/profiles/per-user/termux"
for name in nix nix-shell nix-env nix-store nix-build nix-channel nix-collect-garbage nix-copy-closure nix-hash nix-instantiate nix-prefetch-url; do
	test -x "$tmp/prefix/bin/$name"
	grep -q 'nix-termux managed wrapper' "$tmp/prefix/bin/$name"
	grep -q "exec '$tmp/prefix/bin/nix-termux' exec $name" "$tmp/prefix/bin/$name"
done
grep -qx 'printf '\''%s\\n'\'' original nix-hash' "$tmp/home/.nix-termux/share/prefix-backup/nix-hash"

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" doctor

grep -qx -- "-b" "$tmp/home/.nix-termux/proot.args"
grep -qx -- "$tmp/home/.nix-termux/tmp:/tmp" "$tmp/home/.nix-termux/proot.args"
grep -qx 'nameserver 192.0.2.53' "$tmp/home/.nix-termux/root/etc/resolv.conf"

doctor_json=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" doctor --json
)

printf '%s\n' "$doctor_json" | jq -e \
	--arg sha "$sha" \
	'.ok == true
	and .termux.ok == true
	and .proot.ok == true
	and .store.ok == true
	and .nix.ok == true
	and .nixConf.ok == true
	and .certs.ok == true
	and .dns.ok == true
	and .wrappers.ok == true
	and .wrappers.missing == ""
	and .activation.ok == true
	and .activation.bootstrapSha256 == $sha' >/dev/null

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
[ -x "$tmp/prefix/bin/nix-hash" ]
grep -qx 'printf '\''%s\\n'\'' original nix-hash' "$tmp/prefix/bin/nix-hash"
[ ! -d "$tmp/home/.nix-termux" ]

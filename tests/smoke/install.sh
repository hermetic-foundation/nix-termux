#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=${TMPDIR:-/tmp}/nix-termux-smoke.$$

cleanup() {
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp/home" "$tmp/prefix/bin" "$tmp/prefix/etc" "$tmp/fake-bin" "$tmp/no-jq-bin" "$tmp/missing-cat-bin" "$tmp/bootstrap" "$tmp/runtime-source" "$tmp/standalone"
host_sh=$(command -v sh)
host_cat=$(command -v cat)
for command in sh basename cat chmod cp dirname grep gzip head ln mkdir mv rm sed sha256sum tar uname; do
	ln -s "$(command -v "$command")" "$tmp/no-jq-bin/$command"
done
for command in sh basename chmod cp dirname grep head ln mkdir mv rm sed uname; do
	ln -s "$(command -v "$command")" "$tmp/missing-cat-bin/$command"
done
cp "$host_sh" "$tmp/prefix/bin/sh"
cat >"$tmp/prefix/bin/nix-hash" <<EOF
#!$host_sh
printf '%s\n' original nix-hash
EOF
chmod 755 "$tmp/prefix/bin/nix-hash"
cat >"$tmp/prefix/bin/nix-env" <<EOF
#!$host_sh
# mentions nix-termux but is not a managed wrapper
printf '%s\n' original nix-env
EOF
chmod 755 "$tmp/prefix/bin/nix-env"
printf '%s\n' "nameserver 192.0.2.53" >"$tmp/prefix/etc/resolv.conf"
cp "$repo_root/installer/install.sh" "$tmp/standalone/install.sh"
if grep -q 'awk' "$tmp/standalone/install.sh"; then
	printf '%s\n' "standalone installer must not require awk" >&2
	exit 1
fi
mkdir -p "$tmp/runtime-source/bin" "$tmp/runtime-source/installer" "$tmp/runtime-source/runtime" "$tmp/runtime-source/tests/termux"
cp "$repo_root/bin/nix-termux" "$tmp/runtime-source/bin/nix-termux"
cp "$repo_root/installer/install.sh" "$tmp/runtime-source/installer/install.sh"
cp "$repo_root/installer/uninstall.sh" "$tmp/runtime-source/installer/uninstall.sh"
cp "$repo_root/runtime/nix-termux.sh" "$tmp/runtime-source/runtime/nix-termux.sh"
cp "$repo_root/tests/termux/device-smoke.sh" "$tmp/runtime-source/tests/termux/device-smoke.sh"
if grep -Eq '(^|[^[:alnum:]_])awk([^[:alnum:]_]|$)' "$tmp/runtime-source/tests/termux/device-smoke.sh"; then
	printf '%s\n' "device smoke must not require awk" >&2
	exit 1
fi
(cd "$tmp/runtime-source" && tar -czf "$tmp/runtime.tar.gz" .)
runtime_sha=$(sha256sum "$tmp/runtime.tar.gz" | awk '{print $1}')
mkdir -p "$tmp/runtime-missing/runtime" "$tmp/runtime-missing/bin" "$tmp/runtime-missing/installer" "$tmp/runtime-missing/tests/termux"
cp "$repo_root/bin/nix-termux" "$tmp/runtime-missing/bin/nix-termux"
cp "$repo_root/installer/install.sh" "$tmp/runtime-missing/installer/install.sh"
cp "$repo_root/installer/uninstall.sh" "$tmp/runtime-missing/installer/uninstall.sh"
cp "$repo_root/tests/termux/device-smoke.sh" "$tmp/runtime-missing/tests/termux/device-smoke.sh"
(cd "$tmp/runtime-missing" && tar -czf "$tmp/runtime-missing.tar.gz" .)
runtime_missing_sha=$(sha256sum "$tmp/runtime-missing.tar.gz" | awk '{print $1}')
cp -R "$tmp/runtime-source" "$tmp/runtime-unsafe"
(cd "$tmp/runtime-unsafe" && tar --transform='s|^\./bin/nix-termux$|../nix-termux|' -czf "$tmp/runtime-unsafe.tar.gz" .)
runtime_unsafe_sha=$(sha256sum "$tmp/runtime-unsafe.tar.gz" | awk '{print $1}')
cp -R "$tmp/runtime-source" "$tmp/runtime-source-v2"
# shellcheck disable=SC2016
sed 's/version=${NIX_TERMUX_VERSION:-0.1.0}/version=${NIX_TERMUX_VERSION:-0.1.1}/' \
	"$tmp/runtime-source/runtime/nix-termux.sh" >"$tmp/runtime-source-v2/runtime/nix-termux.sh"
(cd "$tmp/runtime-source-v2" && tar -czf "$tmp/runtime-v2.tar.gz" .)
runtime_v2_sha=$(sha256sum "$tmp/runtime-v2.tar.gz" | awk '{print $1}')

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
			export "\$1"
			shift
			;;
		*)
			break
			;;
	esac
done
profile_bin=\${NIX_TERMUX_PROFILE_DIR:-"\$NIX_TERMUX_STATE_DIR/nix/var/nix/profiles/default"}/bin
if [ -x "\$profile_bin/\$1" ]; then
	command=\$1
	shift
	exec "\$profile_bin/\$command" "\$@"
fi
case "\$1" in
	/nix/var/nix/profiles/default/bin/*)
		command=\${1##*/}
		if [ -x "\$profile_bin/\$command" ]; then
			shift
			exec "\$profile_bin/\$command" "\$@"
		fi
		;;
esac
exec "\$@"
EOF
chmod 755 "$tmp/fake-bin/proot"

mkdir -p \
	"$tmp/bootstrap/nix/store" \
	"$tmp/bootstrap/nix/var/nix/profiles/default/bin" \
	"$tmp/bootstrap/nix/var/nix/profiles/default/etc/ssl/certs" \
	"$tmp/bootstrap/root/bin" \
	"$tmp/bootstrap/root/etc/nix" \
	"$tmp/bootstrap/root/usr/bin"
mkdir -p "$tmp/android-storage/sdcard" "$tmp/android-storage/storage"

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
	"$host_cat" >"\$NIX_TERMUX_STATE_DIR/load-db.input"
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
for name in nix-shell nix-env nix-build nix-channel nix-collect-garbage nix-copy-closure nix-hash nix-instantiate nix-prefetch-url; do
	cat >"$tmp/bootstrap/nix/var/nix/profiles/default/bin/$name" <<EOF
#!$host_sh
printf 'fake $name'
for arg in "\$@"; do
	printf ' %s' "\$arg"
done
printf '\n'
EOF
	chmod 755 "$tmp/bootstrap/nix/var/nix/profiles/default/bin/$name"
done
cat >"$tmp/bootstrap/nix/var/nix/profiles/default/bin/bash" <<EOF
#!$host_sh
printf 'fake bash shell=%s' "\$SHELL"
for arg in "\$@"; do
	printf ' %s' "\$arg"
done
printf '\n'
EOF
chmod 755 "$tmp/bootstrap/nix/var/nix/profiles/default/bin/bash"
cp "$(command -v env)" "$tmp/bootstrap/root/usr/bin/env"
cp "$host_sh" "$tmp/bootstrap/root/bin/sh"
printf '%s\n' "experimental-features = nix-command flakes" >"$tmp/bootstrap/root/etc/nix/nix.conf"
cat >"$tmp/bootstrap/root/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/sh
termux:x:1000:1000:termux:/home/termux:/bin/sh
EOF
cat >"$tmp/bootstrap/root/etc/group" <<EOF
root:x:0:
termux:x:1000:
EOF
cat >"$tmp/bootstrap/root/etc/nsswitch.conf" <<EOF
passwd: files
group: files
hosts: files dns
EOF
cat >"$tmp/bootstrap/root/etc/hosts" <<EOF
127.0.0.1 localhost
::1 localhost
EOF
printf '%s\n' nix-termux >"$tmp/bootstrap/root/etc/hostname"
printf '%s\n' "fake cert bundle" >"$tmp/bootstrap/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
mkdir -p "$tmp/bootstrap/nix-termux"
printf '%s\n' "fake registration" >"$tmp/bootstrap/nix-termux/bootstrap.registration"

(cd "$tmp/bootstrap" && tar -czf "$tmp/bootstrap.tar.gz" .)
sha=$(sha256sum "$tmp/bootstrap.tar.gz" | awk '{print $1}')
(cd "$tmp/bootstrap" && tar --transform='s|^\./root/etc/nix/nix.conf$|../nix.conf|' -czf "$tmp/bootstrap-unsafe.tar.gz" .)
unsafe_bootstrap_sha=$(sha256sum "$tmp/bootstrap-unsafe.tar.gz" | awk '{print $1}')
cp -R "$tmp/bootstrap" "$tmp/bootstrap-missing-registration"
rm -f "$tmp/bootstrap-missing-registration/nix-termux/bootstrap.registration"
(cd "$tmp/bootstrap-missing-registration" && tar -czf "$tmp/bootstrap-missing-registration.tar.gz" .)
missing_registration_sha=$(sha256sum "$tmp/bootstrap-missing-registration.tar.gz" | awk '{print $1}')
cp -R "$tmp/bootstrap" "$tmp/bootstrap-missing-identity"
rm -f "$tmp/bootstrap-missing-identity/root/etc/passwd"
(cd "$tmp/bootstrap-missing-identity" && tar -czf "$tmp/bootstrap-missing-identity.tar.gz" .)
missing_identity_sha=$(sha256sum "$tmp/bootstrap-missing-identity.tar.gz" | awk '{print $1}')
cp -R "$tmp/bootstrap" "$tmp/bootstrap-missing-shell"
rm -f "$tmp/bootstrap-missing-shell/root/bin/sh"
(cd "$tmp/bootstrap-missing-shell" && tar -czf "$tmp/bootstrap-missing-shell.tar.gz" .)
missing_shell_sha=$(sha256sum "$tmp/bootstrap-missing-shell.tar.gz" | awk '{print $1}')
cp -R "$tmp/bootstrap" "$tmp/bootstrap-missing-hosts"
rm -f "$tmp/bootstrap-missing-hosts/root/etc/hosts"
(cd "$tmp/bootstrap-missing-hosts" && tar -czf "$tmp/bootstrap-missing-hosts.tar.gz" .)
missing_hosts_sha=$(sha256sum "$tmp/bootstrap-missing-hosts.tar.gz" | awk '{print $1}')
cp -R "$tmp/bootstrap" "$tmp/bootstrap-missing-hostname"
rm -f "$tmp/bootstrap-missing-hostname/root/etc/hostname"
(cd "$tmp/bootstrap-missing-hostname" && tar -czf "$tmp/bootstrap-missing-hostname.tar.gz" .)
missing_hostname_sha=$(sha256sum "$tmp/bootstrap-missing-hostname.tar.gz" | awk '{print $1}')
cp -R "$tmp/bootstrap" "$tmp/bootstrap-load-db-fail"
printf '%s\n' "failed bootstrap marker" >"$tmp/bootstrap-load-db-fail/nix/store/bootstrap-load-db-fail-marker"
cat >"$tmp/bootstrap-load-db-fail/nix/var/nix/profiles/default/bin/nix-store" <<EOF
#!$host_sh
printf '%s\n' "load db failed" >&2
exit 9
EOF
chmod 755 "$tmp/bootstrap-load-db-fail/nix/var/nix/profiles/default/bin/nix-store"
(cd "$tmp/bootstrap-load-db-fail" && tar -czf "$tmp/bootstrap-load-db-fail.tar.gz" .)
load_db_fail_sha=$(sha256sum "$tmp/bootstrap-load-db-fail.tar.gz" | awk '{print $1}')
cat >"$tmp/bootstrap-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "url": "wrong-bootstrap.tar.gz",
  "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
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
cat >"$tmp/bootstrap-unsafe-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "archive": {
    "url": "bootstrap-unsafe.tar.gz",
    "sha256": "$unsafe_bootstrap_sha"
  },
  "layout": {
    "storeDir": "nix",
    "rootDir": "root",
    "nixBin": "nix/var/nix/profiles/default/bin/nix",
    "registration": "nix-termux/bootstrap.registration"
  }
}
EOF
cat >"$tmp/bootstrap-missing-registration-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "archive": {
    "url": "bootstrap-missing-registration.tar.gz",
    "sha256": "$missing_registration_sha"
  },
  "layout": {
    "storeDir": "nix",
    "rootDir": "root",
    "nixBin": "nix/var/nix/profiles/default/bin/nix",
    "registration": "nix-termux/bootstrap.registration"
  }
}
EOF
cat >"$tmp/bootstrap-load-db-fail-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "archive": {
    "url": "bootstrap-load-db-fail.tar.gz",
    "sha256": "$load_db_fail_sha"
  },
  "layout": {
    "storeDir": "nix",
    "rootDir": "root",
    "nixBin": "nix/var/nix/profiles/default/bin/nix",
    "registration": "nix-termux/bootstrap.registration"
  }
}
EOF
cat >"$tmp/bootstrap-missing-identity-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "archive": {
    "url": "bootstrap-missing-identity.tar.gz",
    "sha256": "$missing_identity_sha"
  },
  "layout": {
    "storeDir": "nix",
    "rootDir": "root",
    "nixBin": "nix/var/nix/profiles/default/bin/nix",
    "registration": "nix-termux/bootstrap.registration"
  }
}
EOF
cat >"$tmp/bootstrap-missing-shell-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "archive": {
    "url": "bootstrap-missing-shell.tar.gz",
    "sha256": "$missing_shell_sha"
  },
  "layout": {
    "storeDir": "nix",
    "rootDir": "root",
    "nixBin": "nix/var/nix/profiles/default/bin/nix",
    "registration": "nix-termux/bootstrap.registration"
  }
}
EOF
cat >"$tmp/bootstrap-missing-hosts-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "archive": {
    "url": "bootstrap-missing-hosts.tar.gz",
    "sha256": "$missing_hosts_sha"
  },
  "layout": {
    "storeDir": "nix",
    "rootDir": "root",
    "nixBin": "nix/var/nix/profiles/default/bin/nix",
    "registration": "nix-termux/bootstrap.registration"
  }
}
EOF
cat >"$tmp/bootstrap-missing-hostname-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "archive": {
    "url": "bootstrap-missing-hostname.tar.gz",
    "sha256": "$missing_hostname_sha"
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
  "url": "wrong-runtime.tar.gz",
  "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
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
cat >"$tmp/bootstrap-manifest-no-jq.json" <<EOF
{
  "schemaVersion": 1,
  "url": "wrong-bootstrap-no-jq.tar.gz",
  "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
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
cat >"$tmp/channel-no-jq.json" <<EOF
{
  "schemaVersion": 1,
  "url": "wrong-runtime-no-jq.tar.gz",
  "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "runtime": {
    "url": "runtime.tar.gz",
    "sha256": "$runtime_sha"
  },
  "bootstrapManifest": {
    "url": "bootstrap-manifest-no-jq.json"
  }
}
EOF
cat >"$tmp/channel-v2.json" <<EOF
{
  "schemaVersion": 1,
  "url": "wrong-runtime-v2.tar.gz",
  "sha256": "1111111111111111111111111111111111111111111111111111111111111111",
  "platform": {
    "termuxArch": "x86_64",
    "nixSystem": "x86_64-linux"
  },
  "runtime": {
    "url": "runtime-v2.tar.gz",
    "sha256": "$runtime_v2_sha"
  },
  "bootstrapManifest": {
    "url": "bootstrap-manifest.json"
  }
}
EOF
sed 's/"sha256": "'"$runtime_sha"'"/"sha256": "not-a-sha256"/' \
	"$tmp/channel.json" >"$tmp/channel-bad-runtime-sha.json"
sed 's/"sha256": "'"$sha"'"/"sha256": "not-a-sha256"/' \
	"$tmp/bootstrap-manifest.json" >"$tmp/bootstrap-bad-archive-sha.json"
sed 's/"nixSystem": "x86_64-linux"/"nixSystem": "aarch64-linux"/' \
	"$tmp/channel.json" >"$tmp/channel-bad-nix-system.json"
sed 's/"nixSystem": "x86_64-linux"/"nixSystem": "aarch64-linux"/' \
	"$tmp/bootstrap-manifest.json" >"$tmp/bootstrap-bad-nix-system.json"
cat >"$tmp/bootstrap-missing-layout-registration-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "registration": "nix-termux/bootstrap.registration",
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
    "nixBin": "nix/var/nix/profiles/default/bin/nix"
  }
}
EOF
cat >"$tmp/fake-bin/pkg" <<EOF
#!$host_sh
if [ "\$1" = "--print-architecture" ]; then
	printf '%s\n' x86_64
	exit 0
fi
exit 1
EOF
chmod 755 "$tmp/fake-bin/pkg"
cat >"$tmp/fake-bin/curl" <<EOF
#!$host_sh
case " \$* " in
*" https://example.invalid/missing-channel.json "*)
	printf '%s\n' "curl: (22) The requested URL returned error: 404" >&2
	exit 22
	;;
*)
	printf 'unexpected curl invocation:' >&2
	for arg in "\$@"; do
		printf ' %s' "\$arg" >&2
	done
	printf '\n' >&2
	exit 2
	;;
esac
EOF
chmod 755 "$tmp/fake-bin/curl"
cp "$tmp/fake-bin/proot" "$tmp/no-jq-bin/proot"
cp "$tmp/fake-bin/pkg" "$tmp/no-jq-bin/pkg"
cp "$tmp/fake-bin/proot" "$tmp/missing-cat-bin/proot"
cp "$tmp/fake-bin/pkg" "$tmp/missing-cat-bin/pkg"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/install-extra-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/install-extra-home/.nix-termux" \
	sh "$tmp/standalone/install.sh" extra >"$tmp/install-extra.out" 2>"$tmp/install-extra.err"; then
	printf '%s\n' "install with extra arguments unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^install.sh: install accepts no arguments$' "$tmp/install-extra.err"
test ! -e "$tmp/install-extra-home/.nix-termux/etc/nix-termux.conf"
test ! -e "$tmp/prefix/bin/nix"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/state-root-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR=/ \
	sh "$tmp/standalone/install.sh" 2>"$tmp/install-state-root.err"; then
	printf '%s\n' "install with root state dir unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^install.sh: NIX_TERMUX_STATE_DIR must not be /$' "$tmp/install-state-root.err"
test ! -e "$tmp/state-root-home/.nix-termux/etc/nix-termux.conf"
test ! -e "$tmp/prefix/bin/nix"

if NIX_TERMUX_STATE_DIR=/ \
	sh "$repo_root/runtime/nix-termux.sh" version >"$tmp/runtime-state-root.out" 2>"$tmp/runtime-state-root.err"; then
	printf '%s\n' "runtime with root state dir unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^nix-termux: NIX_TERMUX_STATE_DIR must not be /$' "$tmp/runtime-state-root.err"

if HOME="$tmp/state-root-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR=/ \
	sh "$repo_root/installer/uninstall.sh" >"$tmp/uninstall-state-root.out" 2>"$tmp/uninstall-state-root.err"; then
	printf '%s\n' "uninstall with root state dir unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^uninstall.sh: NIX_TERMUX_STATE_DIR must not be /$' "$tmp/uninstall-state-root.err"
test ! -e "$tmp/prefix/bin/nix"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/prefix-root-home" \
	PREFIX=/ \
	NIX_TERMUX_STATE_DIR="$tmp/prefix-root-home/.nix-termux" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/install-prefix-root.err"; then
	printf '%s\n' "install with root prefix unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^install.sh: PREFIX must not be /$' "$tmp/install-prefix-root.err"
test ! -e "$tmp/prefix-root-home/.nix-termux/etc/nix-termux.conf"
test ! -e "$tmp/prefix-root-home/.nix-profile"

if PREFIX=/ \
	NIX_TERMUX_STATE_DIR="$tmp/prefix-root-home/.nix-termux" \
	sh "$repo_root/runtime/nix-termux.sh" version >"$tmp/runtime-prefix-root.out" 2>"$tmp/runtime-prefix-root.err"; then
	printf '%s\n' "runtime with root prefix unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^nix-termux: PREFIX must not be /$' "$tmp/runtime-prefix-root.err"

if HOME="$tmp/prefix-root-home" \
	PREFIX=/ \
	NIX_TERMUX_STATE_DIR="$tmp/prefix-root-home/.nix-termux" \
	sh "$repo_root/installer/uninstall.sh" >"$tmp/uninstall-prefix-root.out" 2>"$tmp/uninstall-prefix-root.err"; then
	printf '%s\n' "uninstall with root prefix unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^uninstall.sh: PREFIX must not be /$' "$tmp/uninstall-prefix-root.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME=/ \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home-root-state" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/install-home-root.err"; then
	printf '%s\n' "install with root home unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^install.sh: HOME must not be /$' "$tmp/install-home-root.err"
test ! -e "$tmp/home-root-state/etc/nix-termux.conf"
test ! -e "$tmp/prefix/bin/nix"

if HOME=/ \
	NIX_TERMUX_STATE_DIR="$tmp/home-root-state" \
	sh "$repo_root/runtime/nix-termux.sh" version >"$tmp/runtime-home-root.out" 2>"$tmp/runtime-home-root.err"; then
	printf '%s\n' "runtime with root home unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^nix-termux: HOME must not be /$' "$tmp/runtime-home-root.err"

if HOME=/ \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home-root-state" \
	sh "$repo_root/installer/uninstall.sh" >"$tmp/uninstall-home-root.out" 2>"$tmp/uninstall-home-root.err"; then
	printf '%s\n' "uninstall with root home unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^uninstall.sh: HOME must not be /$' "$tmp/uninstall-home-root.err"
test ! -e "$tmp/prefix/bin/nix"

if env \
	PATH="$tmp/fake-bin:$PATH" \
	HOME= \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home-empty-state" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/install-home-empty.err"; then
	printf '%s\n' "install with empty home unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^install.sh: HOME must not be empty$' "$tmp/install-home-empty.err"
test ! -e "$tmp/home-empty-state/etc/nix-termux.conf"
test ! -e "$tmp/prefix/bin/nix"

if env \
	HOME= \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home-empty-state" \
	sh "$repo_root/installer/uninstall.sh" >"$tmp/uninstall-home-empty.out" 2>"$tmp/uninstall-home-empty.err"; then
	printf '%s\n' "uninstall with empty home unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^uninstall.sh: HOME must not be empty$' "$tmp/uninstall-home-empty.err"
test ! -e "$tmp/prefix/bin/nix"

if PATH="$tmp/missing-cat-bin" \
	HOME="$tmp/missing-cat-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/missing-cat-home/.nix-termux" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/missing-cat.err"; then
	printf '%s\n' "install without cat unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'install.sh: required command missing: cat' "$tmp/missing-cat.err"
test ! -e "$tmp/missing-cat-home/.nix-termux/etc/nix-termux.conf"
test ! -e "$tmp/prefix/bin/nix"

mkdir -p "$tmp/no-jq-prefix/bin" "$tmp/no-jq-prefix/etc"
cp "$host_sh" "$tmp/no-jq-prefix/bin/sh"
printf '%s\n' "nameserver 192.0.2.54" >"$tmp/no-jq-prefix/etc/resolv.conf"
PATH="$tmp/no-jq-bin" \
	HOME="$tmp/no-jq-home" \
	PREFIX="$tmp/no-jq-prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/no-jq-home/.nix-termux" \
	NIX_TERMUX_CHANNEL_URL="file://$tmp/channel-no-jq.json" \
	sh "$tmp/standalone/install.sh" >"$tmp/no-jq-install.out"
grep -q '^loaded db$' "$tmp/no-jq-install.out"
grep -q '^runtime_version=0.1.0$' "$tmp/no-jq-home/.nix-termux/etc/nix-termux.conf"
grep -q '^channel_url=file://.*/channel-no-jq.json$' "$tmp/no-jq-home/.nix-termux/etc/nix-termux.conf"
grep -q '^bootstrap_manifest_url=file://.*/bootstrap-manifest-no-jq.json$' "$tmp/no-jq-home/.nix-termux/etc/nix-termux.conf"
grep -q "^runtime_archive_sha256=$runtime_sha$" "$tmp/no-jq-home/.nix-termux/etc/nix-termux.conf"
grep -q "^bootstrap_sha256=$sha$" "$tmp/no-jq-home/.nix-termux/etc/nix-termux.conf"
test -x "$tmp/no-jq-prefix/bin/nix"

mkdir -p "$tmp/trailing-base-prefix/bin" "$tmp/trailing-base-prefix/etc"
cp "$host_sh" "$tmp/trailing-base-prefix/bin/sh"
printf '%s\n' "nameserver 192.0.2.54" >"$tmp/trailing-base-prefix/etc/resolv.conf"
PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/trailing-base-home" \
	PREFIX="$tmp/trailing-base-prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/trailing-base-home/.nix-termux" \
	NIX_TERMUX_CHANNEL_BASE_URL="file://$tmp/" \
	sh "$tmp/standalone/install.sh" >"$tmp/trailing-base-install.out"
grep -qx "channel_base_url=file://$tmp/" "$tmp/trailing-base-home/.nix-termux/etc/nix-termux.conf"
grep -qx "channel_url=file://$tmp/nix-termux-channel-x86_64.json" "$tmp/trailing-base-home/.nix-termux/etc/nix-termux.conf"
grep -qx "bootstrap_manifest_url=file://$tmp/bootstrap-manifest.json" "$tmp/trailing-base-home/.nix-termux/etc/nix-termux.conf"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/no-channel-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/no-channel-home/.nix-termux" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/no-channel.err"; then
	printf '%s\n' "standalone install without channel unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'runtime files not found; set NIX_TERMUX_CHANNEL_BASE_URL, NIX_TERMUX_CHANNEL_URL, or NIX_TERMUX_RUNTIME_ARCHIVE_URL' "$tmp/no-channel.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/fetch-fail-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/fetch-fail-home/.nix-termux" \
	NIX_TERMUX_CHANNEL_URL=https://example.invalid/missing-channel.json \
	sh "$tmp/standalone/install.sh" 2>"$tmp/fetch-fail.err"; then
	printf '%s\n' "failed fetch unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'curl: (22) The requested URL returned error: 404' "$tmp/fetch-fail.err"
grep -q 'install.sh: failed to fetch https://example.invalid/missing-channel.json' "$tmp/fetch-fail.err"
test ! -e "$tmp/fetch-fail-home/.nix-termux/etc/nix-termux.conf"
test ! -e "$tmp/prefix/bin/nix"

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
	HOME="$tmp/channel-bad-runtime-sha-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/channel-bad-runtime-sha-home/.nix-termux" \
	NIX_TERMUX_CHANNEL_URL="file://$tmp/channel-bad-runtime-sha.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/channel-bad-runtime-sha.err"; then
	printf '%s\n' "bad channel runtime sha unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'channel manifest runtime.sha256 must be a 64-character lowercase hex string' "$tmp/channel-bad-runtime-sha.err"
test ! -e "$tmp/channel-bad-runtime-sha-home/.nix-termux/runtime/nix-termux.sh"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/channel-bad-nix-system-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/channel-bad-nix-system-home/.nix-termux" \
	NIX_TERMUX_CHANNEL_URL="file://$tmp/channel-bad-nix-system.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/channel-bad-nix-system.err"; then
	printf '%s\n' "bad channel nix system unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'channel manifest nix system mismatch: expected x86_64-linux got aarch64-linux' "$tmp/channel-bad-nix-system.err"
test ! -e "$tmp/channel-bad-nix-system-home/.nix-termux/runtime/nix-termux.sh"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/runtime-bad-env-sha-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/runtime-bad-env-sha-home/.nix-termux" \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256=not-a-sha256 \
	sh "$tmp/standalone/install.sh" 2>"$tmp/runtime-bad-env-sha.err"; then
	printf '%s\n' "bad runtime env sha unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'NIX_TERMUX_RUNTIME_ARCHIVE_SHA256 must be a 64-character lowercase hex string' "$tmp/runtime-bad-env-sha.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/runtime-missing-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/runtime-missing-home/.nix-termux" \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime-missing.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_missing_sha" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/runtime-missing.err"; then
	printf '%s\n' "runtime archive missing runtime script unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'runtime archive missing runtime/nix-termux.sh' "$tmp/runtime-missing.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/runtime-unsafe-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/runtime-unsafe-home/.nix-termux" \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime-unsafe.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_unsafe_sha" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/runtime-unsafe.err"; then
	printf '%s\n' "unsafe runtime archive unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'runtime archive contains unsafe path: ../nix-termux' "$tmp/runtime-unsafe.err"
test ! -e "$tmp/runtime-unsafe-home/nix-termux"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/mismatch-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/mismatch-home/.nix-termux" \
	NIX_TERMUX_ARCH=aarch64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-manifest.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-mismatch.err"; then
	printf '%s\n' "wrong-arch bootstrap install unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap manifest architecture mismatch: expected aarch64 got x86_64' "$tmp/bootstrap-mismatch.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-bad-archive-sha-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-bad-archive-sha-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-bad-archive-sha.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-bad-archive-sha.err"; then
	printf '%s\n' "bad bootstrap archive sha unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap manifest archive.sha256 must be a 64-character lowercase hex string' "$tmp/bootstrap-bad-archive-sha.err"
test ! -e "$tmp/bootstrap-bad-archive-sha-home/.nix-termux/etc/bootstrap-activation.conf"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-bad-nix-system-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-bad-nix-system-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-bad-nix-system.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-bad-nix-system.err"; then
	printf '%s\n' "bad bootstrap nix system unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap manifest nix system mismatch: expected x86_64-linux got aarch64-linux' "$tmp/bootstrap-bad-nix-system.err"
test ! -e "$tmp/bootstrap-bad-nix-system-home/.nix-termux/etc/bootstrap-activation.conf"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-bad-env-sha-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-bad-env-sha-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_URL="file://$tmp/bootstrap.tar.gz" \
	NIX_TERMUX_BOOTSTRAP_SHA256=not-a-sha256 \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-bad-env-sha.err"; then
	printf '%s\n' "bad bootstrap env sha unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'NIX_TERMUX_BOOTSTRAP_SHA256 must be a 64-character lowercase hex string' "$tmp/bootstrap-bad-env-sha.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-missing-layout-registration-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-missing-layout-registration-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-missing-layout-registration-manifest.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-missing-layout-registration.err"; then
	printf '%s\n' "bootstrap missing layout registration unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap manifest missing layout.registration' "$tmp/bootstrap-missing-layout-registration.err"
test ! -e "$tmp/bootstrap-missing-layout-registration-home/.nix-termux/etc/bootstrap-activation.conf"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-unsafe-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-unsafe-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-unsafe-manifest.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-unsafe.err"; then
	printf '%s\n' "unsafe bootstrap archive unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap archive contains unsafe path: ../nix.conf' "$tmp/bootstrap-unsafe.err"
test ! -e "$tmp/bootstrap-unsafe-home/nix.conf"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-missing-registration-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-missing-registration-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-missing-registration-manifest.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-missing-registration.err"; then
	printf '%s\n' "bootstrap missing registration unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap archive missing nix-termux/bootstrap.registration' "$tmp/bootstrap-missing-registration.err"
test ! -e "$tmp/bootstrap-missing-registration-home/.nix-termux/etc/bootstrap-activation.conf"
test ! -e "$tmp/prefix/bin/nix"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-missing-identity-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-missing-identity-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-missing-identity-manifest.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-missing-identity.err"; then
	printf '%s\n' "bootstrap missing identity unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap archive missing root/etc/passwd' "$tmp/bootstrap-missing-identity.err"
test ! -e "$tmp/bootstrap-missing-identity-home/.nix-termux/etc/bootstrap-activation.conf"
test ! -e "$tmp/prefix/bin/nix"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-missing-shell-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-missing-shell-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-missing-shell-manifest.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-missing-shell.err"; then
	printf '%s\n' "bootstrap missing shell unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap archive missing root/bin/sh' "$tmp/bootstrap-missing-shell.err"
test ! -e "$tmp/bootstrap-missing-shell-home/.nix-termux/etc/bootstrap-activation.conf"
test ! -e "$tmp/prefix/bin/nix"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-missing-hosts-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-missing-hosts-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-missing-hosts-manifest.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-missing-hosts.err"; then
	printf '%s\n' "bootstrap missing hosts unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap archive missing root/etc/hosts' "$tmp/bootstrap-missing-hosts.err"
test ! -e "$tmp/bootstrap-missing-hosts-home/.nix-termux/etc/bootstrap-activation.conf"
test ! -e "$tmp/prefix/bin/nix"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-missing-hostname-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-missing-hostname-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-missing-hostname-manifest.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-missing-hostname.err"; then
	printf '%s\n' "bootstrap missing hostname unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'bootstrap archive missing root/etc/hostname' "$tmp/bootstrap-missing-hostname.err"
test ! -e "$tmp/bootstrap-missing-hostname-home/.nix-termux/etc/bootstrap-activation.conf"
test ! -e "$tmp/prefix/bin/nix"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/bootstrap-load-db-fail-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/bootstrap-load-db-fail-home/.nix-termux" \
	NIX_TERMUX_ARCH=x86_64 \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL="file://$tmp/bootstrap-load-db-fail-manifest.json" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/bootstrap-load-db-fail.err"; then
	printf '%s\n' "bootstrap load-db failure unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'load db failed' "$tmp/bootstrap-load-db-fail.err"
test ! -e "$tmp/bootstrap-load-db-fail-home/.nix-termux/etc/bootstrap-activation.conf"
test ! -e "$tmp/bootstrap-load-db-fail-home/.nix-termux/etc/nix-termux.conf"
test ! -e "$tmp/bootstrap-load-db-fail-home/.nix-profile"
test ! -e "$tmp/prefix/bin/nix"

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	NIX_TERMUX_CHANNEL_BASE_URL="file://$tmp" \
	sh "$tmp/standalone/install.sh"

grep -q '^fake registration$' "$tmp/home/.nix-termux/load-db.input"
grep -q '^registration_loaded=yes$' "$tmp/home/.nix-termux/etc/bootstrap-activation.conf"
grep -q '^bootstrap_manifest_url=file://.*/bootstrap-manifest.json$' "$tmp/home/.nix-termux/etc/bootstrap-activation.conf"
grep -q "^bootstrap_sha256=$sha$" "$tmp/home/.nix-termux/etc/bootstrap-activation.conf"
grep -q '^termux_arch=x86_64$' "$tmp/home/.nix-termux/etc/nix-termux.conf"
grep -q '^runtime_version=0.1.0$' "$tmp/home/.nix-termux/etc/nix-termux.conf"
grep -q '^channel_url=file://.*/nix-termux-channel-x86_64.json$' "$tmp/home/.nix-termux/etc/nix-termux.conf"
grep -q "^runtime_archive_sha256=$runtime_sha$" "$tmp/home/.nix-termux/etc/nix-termux.conf"
test -x "$tmp/home/.nix-termux/share/tests/device-smoke.sh"
test -L "$tmp/home/.nix-profile"
[ "$(readlink "$tmp/home/.nix-profile")" = "/nix/var/nix/profiles/per-user/termux/profile" ]
if find "$tmp/home/.nix-termux" -name '.install.*' | grep -q .; then
	printf '%s\n' "temporary install files left after install" >&2
	exit 1
fi
test ! -e "$tmp/home/.nix-termux/tmp/runtime.tar.gz"
test ! -e "$tmp/home/.nix-termux/tmp/runtime-source"
test ! -e "$tmp/home/.nix-termux/tmp/bootstrap.tar.gz"
test ! -e "$tmp/home/.nix-termux/tmp/bootstrap-stage"
cat >"$tmp/home/.nix-termux/share/tests/device-smoke.sh" <<'EOF'
#!/usr/bin/env sh
printf 'stub device smoke'
for arg in "$@"; do
	printf ' %s' "$arg"
done
printf '\n'
EOF
chmod 755 "$tmp/home/.nix-termux/share/tests/device-smoke.sh"
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
grep -qx '# mentions nix-termux but is not a managed wrapper' "$tmp/home/.nix-termux/share/prefix-backup/nix-env"

quote_home="$tmp/quote'home"
quote_prefix="$tmp/quote'prefix"
mkdir -p "$quote_home" "$quote_prefix/bin" "$quote_prefix/etc"
cp "$host_sh" "$quote_prefix/bin/sh"
printf '%s\n' "nameserver 192.0.2.54" >"$quote_prefix/etc/resolv.conf"
PATH="$tmp/fake-bin:$PATH" \
	HOME="$quote_home" \
	PREFIX="$quote_prefix" \
	NIX_TERMUX_STATE_DIR="$quote_home/.nix-termux" \
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
	sh "$tmp/standalone/install.sh" >/dev/null
quote_version=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$quote_home" \
		PREFIX="$quote_prefix" \
		NIX_TERMUX_STATE_DIR="$quote_home/.nix-termux" \
		"$quote_prefix/bin/nix-termux" version
)
[ "$quote_version" = "0.1.0" ] || {
	printf 'unexpected quoted path version output: %s\n' "$quote_version" >&2
	exit 1
}
mkdir -p "$quote_home/.nix-termux/nix/var/nix/profiles/default/bin"
cat >"$quote_home/.nix-termux/nix/var/nix/profiles/default/bin/nix" <<EOF
#!$host_sh
printf 'quoted fake nix'
for arg in "\$@"; do
	printf ' %s' "\$arg"
done
printf '\n'
EOF
chmod 755 "$quote_home/.nix-termux/nix/var/nix/profiles/default/bin/nix"
quote_nix_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$quote_home" \
		PREFIX="$quote_prefix" \
		NIX_TERMUX_STATE_DIR="$quote_home/.nix-termux" \
		"$quote_prefix/bin/nix" --version
)
[ "$quote_nix_output" = "quoted fake nix --version" ] || {
	printf 'unexpected quoted path nix output: %s\n' "$quote_nix_output" >&2
	exit 1
}

for name in nix nix-shell nix-env nix-store nix-build nix-channel nix-collect-garbage nix-copy-closure nix-hash nix-instantiate nix-prefetch-url; do
	output=$(
		PATH="$tmp/fake-bin:$PATH" \
			HOME="$tmp/home" \
			PREFIX="$tmp/prefix" \
			NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
			"$tmp/prefix/bin/$name" --version
	)
	[ "$output" = "fake $name --version" ] || {
		printf 'unexpected %s wrapper output: %s\n' "$name" "$output" >&2
		exit 1
	}
done

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" doctor

version_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" version
)
[ "$version_output" = "0.1.0" ] || {
	printf 'unexpected version output: %s\n' "$version_output" >&2
	exit 1
}

help_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" help
)
printf '%s\n' "$help_output" | grep -q '^Usage: nix-termux <command> \[args\]$'

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" help extra >"$tmp/help-extra.out" 2>"$tmp/help-extra.err"; then
	printf '%s\n' "help with extra arguments unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^nix-termux: help accepts no arguments$' "$tmp/help-extra.err"

smoke_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" smoke-test --host-stub
)
[ "$smoke_output" = "stub device smoke --host-stub" ] || {
	printf 'unexpected smoke-test output: %s\n' "$smoke_output" >&2
	exit 1
}

enter_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" enter
)
[ "$enter_output" = "fake bash shell=/nix/var/nix/profiles/default/bin/bash -l" ] || {
	printf 'unexpected enter output: %s\n' "$enter_output" >&2
	exit 1
}

grep -qx -- "-b" "$tmp/home/.nix-termux/proot.args"
grep -qx -- "$tmp/home/.nix-termux/tmp:/tmp" "$tmp/home/.nix-termux/proot.args"
grep -qx -- "SHELL=/nix/var/nix/profiles/default/bin/bash" "$tmp/home/.nix-termux/proot.args"
grep -qx -- "/nix/var/nix/profiles/default/bin/bash" "$tmp/home/.nix-termux/proot.args"
grep -qx 'nameserver 192.0.2.53' "$tmp/home/.nix-termux/root/etc/resolv.conf"
test -d "$tmp/home/.cache"
test -d "$tmp/home/.config"
test -d "$tmp/home/.local/share"
test -d "$tmp/home/.local/state"
test -L "$tmp/home/.nix-profile"
[ "$(readlink "$tmp/home/.nix-profile")" = "/nix/var/nix/profiles/per-user/termux/profile" ]

doctor_json=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" doctor --json
)

printf '%s\n' "$doctor_json" | grep -Eq '"runtimeVersion"[[:space:]]*:[[:space:]]*"0.1.0"'
printf '%s\n' "$doctor_json" | grep -Eq '"installedRuntimeVersion"[[:space:]]*:[[:space:]]*"0.1.0"'
printf '%s\n' "$doctor_json" | jq -e \
	--arg sha "$sha" \
	--arg runtime_sha "$runtime_sha" \
	'.schemaVersion == 1
	and .runtimeVersion == "0.1.0"
	and .installedRuntimeVersion == "0.1.0"
	and (.config.path | endswith("/etc/nix-termux.conf"))
	and (.config.channelUrl | test("^file://.*/nix-termux-channel-x86_64.json$"))
	and .config.runtimeArchiveSha256 == $runtime_sha
	and (.config.bootstrapManifestUrl | test("^file://.*/bootstrap-manifest.json$"))
	and .ok == true
	and .termux.ok == true
	and .proot.ok == true
	and .store.ok == true
	and .nix.ok == true
	and .userProfile.ok == true
	and .homeProfile.ok == true
	and .nixConf.ok == true
	and .certs.ok == true
	and .dns.ok == true
	and .wrappers.ok == true
	and .wrappers.missing == ""
	and .activation.ok == true
	and .activation.bootstrapSha256 == $sha' >/dev/null

grep -q '^bootstrap_manifest_url=file://.*/bootstrap-manifest.json$' "$tmp/home/.nix-termux/etc/nix-termux.conf"

printf '%s\n' "live bootstrap marker" >"$tmp/home/.nix-termux/nix/store/live-marker"
if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" upgrade-bootstrap "file://$tmp/bootstrap-load-db-fail-manifest.json" 2>"$tmp/bootstrap-upgrade-load-db-fail.err"; then
	printf '%s\n' "failed bootstrap upgrade unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'load db failed' "$tmp/bootstrap-upgrade-load-db-fail.err"
grep -qx 'live bootstrap marker' "$tmp/home/.nix-termux/nix/store/live-marker"
grep -q '^bootstrap_manifest_url=file://.*/bootstrap-manifest.json$' "$tmp/home/.nix-termux/etc/bootstrap-activation.conf"
grep -q "^bootstrap_sha256=$sha$" "$tmp/home/.nix-termux/etc/bootstrap-activation.conf"
test ! -e "$tmp/home/.nix-termux/nix/store/bootstrap-load-db-fail-marker"

rm "$tmp/home/.nix-profile"
printf '%s\n' "not a profile directory" >"$tmp/home/.nix-profile"
if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" doctor --json >"$tmp/doctor-bad-home-profile.json"; then
	printf '%s\n' "doctor unexpectedly accepted regular .nix-profile file" >&2
	exit 1
fi
jq -e '.ok == false and .homeProfile.ok == false' "$tmp/doctor-bad-home-profile.json" >/dev/null
rm "$tmp/home/.nix-profile"
ln -s /wrong/profile "$tmp/home/.nix-profile"
if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" doctor --json >"$tmp/doctor-bad-home-profile-link.json"; then
	printf '%s\n' "doctor unexpectedly accepted wrong .nix-profile symlink" >&2
	exit 1
fi
jq -e '.ok == false and .homeProfile.ok == false' "$tmp/doctor-bad-home-profile-link.json" >/dev/null
rm "$tmp/home/.nix-profile"
mkdir "$tmp/home/.nix-profile"
PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" doctor --json >"$tmp/doctor-home-profile-dir.json"
jq -e '.ok == true and .homeProfile.ok == true' "$tmp/doctor-home-profile-dir.json" >/dev/null
rm -r "$tmp/home/.nix-profile"
ln -s /nix/var/nix/profiles/per-user/termux/profile "$tmp/home/.nix-profile"

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" upgrade-bootstrap

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" upgrade "file://$tmp/channel-v2.json"

upgraded_version_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" version
)
[ "$upgraded_version_output" = "0.1.1" ] || {
	printf 'unexpected upgraded version output: %s\n' "$upgraded_version_output" >&2
	exit 1
}
grep -q '^runtime_version=0.1.1$' "$tmp/home/.nix-termux/etc/nix-termux.conf"
grep -q "^runtime_archive_sha256=$runtime_v2_sha$" "$tmp/home/.nix-termux/etc/nix-termux.conf"
grep -q '^channel_url=file://.*/channel-v2.json$' "$tmp/home/.nix-termux/etc/nix-termux.conf"
if find "$tmp/home/.nix-termux" -name '.install.*' | grep -q .; then
	printf '%s\n' "temporary install files left after upgrade" >&2
	exit 1
fi
test ! -e "$tmp/home/.nix-termux/tmp/runtime.tar.gz"
test ! -e "$tmp/home/.nix-termux/tmp/runtime-source"
test ! -e "$tmp/home/.nix-termux/tmp/bootstrap.tar.gz"
test ! -e "$tmp/home/.nix-termux/tmp/bootstrap-stage"

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

# shellcheck disable=SC2016
xdg_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" exec sh -c 'printf "%s|%s|%s|%s\n" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"'
)
[ "$xdg_output" = "/home/termux/.config|/home/termux/.cache|/home/termux/.local/share|/home/termux/.local/state" ] || {
	printf 'unexpected XDG output: %s\n' "$xdg_output" >&2
	exit 1
}

# shellcheck disable=SC2016
remote_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		NIX_REMOTE=daemon \
		"$tmp/prefix/bin/nix-termux" exec sh -c 'printf "%s\n" "$NIX_REMOTE"'
)
[ "$remote_output" = "local" ] || {
	printf 'unexpected NIX_REMOTE output: %s\n' "$remote_output" >&2
	exit 1
}

# shellcheck disable=SC2016
nix_path_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		NIX_PATH='' \
		"$tmp/prefix/bin/nix-termux" exec sh -c 'printf "%s\n" "$NIX_PATH"'
)
[ "$nix_path_output" = "nixpkgs=flake:nixpkgs" ] || {
	printf 'unexpected NIX_PATH output: %s\n' "$nix_path_output" >&2
	exit 1
}

# shellcheck disable=SC2016
nix_path_override_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		NIX_TERMUX_NIX_PATH="nixpkgs=$tmp/nixpkgs" \
		"$tmp/prefix/bin/nix-termux" exec sh -c 'printf "%s\n" "$NIX_PATH"'
)
[ "$nix_path_override_output" = "nixpkgs=$tmp/nixpkgs" ] || {
	printf 'unexpected NIX_PATH override output: %s\n' "$nix_path_override_output" >&2
	exit 1
}

# shellcheck disable=SC2016
cert_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" exec sh -c 'printf "%s|%s\n" "$NIX_SSL_CERT_FILE" "$SSL_CERT_FILE"'
)
[ "$cert_output" = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt|/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt" ] || {
	printf 'unexpected cert output: %s\n' "$cert_output" >&2
	exit 1
}

# shellcheck disable=SC2016
profiles_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" exec sh -c 'printf "%s\n" "$NIX_PROFILES"'
)
[ "$profiles_output" = "/nix/var/nix/profiles/default /nix/var/nix/profiles/per-user/termux/profile" ] || {
	printf 'unexpected NIX_PROFILES output: %s\n' "$profiles_output" >&2
	exit 1
}

# shellcheck disable=SC2016
path_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		"$tmp/prefix/bin/nix-termux" exec sh -c 'printf "%s\n" "$PATH"'
)
[ "$path_output" = "/home/termux/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/termux/bin:/usr/bin:/bin" ] || {
	printf 'unexpected PATH output: %s\n' "$path_output" >&2
	exit 1
}

rm "$tmp/home/.nix-profile"
PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	NIX_TERMUX_MANAGE_HOME_PROFILE=no \
	"$tmp/prefix/bin/nix-termux" exec nix --version >/dev/null
test ! -e "$tmp/home/.nix-profile"
if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	NIX_TERMUX_MANAGE_HOME_PROFILE=maybe \
	"$tmp/prefix/bin/nix-termux" exec nix --version >"$tmp/manage-home-profile-invalid.out" 2>"$tmp/manage-home-profile-invalid.err"; then
	printf '%s\n' "invalid NIX_TERMUX_MANAGE_HOME_PROFILE unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^nix-termux: NIX_TERMUX_MANAGE_HOME_PROFILE must be yes or no$' "$tmp/manage-home-profile-invalid.err"
ln -s /nix/var/nix/profiles/per-user/termux/profile "$tmp/home/.nix-profile"

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	NIX_TERMUX_ANDROID_BIND_DIRS="$tmp/android-storage/sdcard $tmp/android-storage/storage $tmp/android-storage/missing" \
	"$tmp/prefix/bin/nix-termux" exec nix --version >/dev/null
grep -qx -- "$tmp/android-storage/sdcard:$tmp/android-storage/sdcard" "$tmp/home/.nix-termux/proot.args"
grep -qx -- "$tmp/android-storage/storage:$tmp/android-storage/storage" "$tmp/home/.nix-termux/proot.args"
if grep -qx -- "$tmp/android-storage/missing:$tmp/android-storage/missing" "$tmp/home/.nix-termux/proot.args"; then
	printf '%s\n' "missing Android bind path was passed to proot" >&2
	exit 1
fi
(
	cd "$tmp"
	mkdir -p relative-bind
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		NIX_TERMUX_ANDROID_BIND_DIRS="relative-bind $tmp/android-storage/sdcard" \
		"$tmp/prefix/bin/nix-termux" exec nix --version >/dev/null
)
grep -qx -- "$tmp/android-storage/sdcard:$tmp/android-storage/sdcard" "$tmp/home/.nix-termux/proot.args"
if grep -qx -- "relative-bind:relative-bind" "$tmp/home/.nix-termux/proot.args"; then
	printf '%s\n' "relative Android bind path was passed to proot" >&2
	exit 1
fi

env_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		NIX_PATH='' \
		"$tmp/prefix/bin/nix-termux" env
)
printf '%s\n' "$env_output" | grep -q '^NIX_TERMUX_VERSION=0.1.1$'
printf '%s\n' "$env_output" | grep -q '^NIX_TERMUX_ANDROID_BIND_DIRS=/sdcard /storage$'
printf '%s\n' "$env_output" | grep -q "^XDG_CONFIG_HOME=$tmp/home/.config$"
printf '%s\n' "$env_output" | grep -q "^XDG_CACHE_HOME=$tmp/home/.cache$"
printf '%s\n' "$env_output" | grep -q "^XDG_DATA_HOME=$tmp/home/.local/share$"
printf '%s\n' "$env_output" | grep -q "^XDG_STATE_HOME=$tmp/home/.local/state$"
printf '%s\n' "$env_output" | grep -q '^PATH=/home/termux/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/termux/bin:/usr/bin:/bin$'
printf '%s\n' "$env_output" | grep -q '^NIX_CONF_DIR=/etc/nix$'
printf '%s\n' "$env_output" | grep -q '^NIX_REMOTE=local$'
printf '%s\n' "$env_output" | grep -q '^NIX_PATH=nixpkgs=flake:nixpkgs$'
printf '%s\n' "$env_output" | grep -q '^NIX_PROFILES=/nix/var/nix/profiles/default /nix/var/nix/profiles/per-user/termux/profile$'
printf '%s\n' "$env_output" | grep -q '^SHELL=/nix/var/nix/profiles/default/bin/bash$'
printf '%s\n' "$env_output" | grep -q '^NIX_SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt$'
printf '%s\n' "$env_output" | grep -q '^SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt$'

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" env extra >"$tmp/env-extra.out" 2>"$tmp/env-extra.err"; then
	printf '%s\n' "env with extra arguments unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^nix-termux: env accepts no arguments$' "$tmp/env-extra.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" upgrade-bootstrap \
	"file://$tmp/bootstrap-manifest.json" extra >"$tmp/upgrade-bootstrap-extra.out" 2>"$tmp/upgrade-bootstrap-extra.err"; then
	printf '%s\n' "upgrade-bootstrap with extra arguments unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^nix-termux: upgrade-bootstrap accepts at most one manifest URL$' "$tmp/upgrade-bootstrap-extra.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" upgrade "" >"$tmp/upgrade-empty.out" 2>"$tmp/upgrade-empty.err"; then
	printf '%s\n' "upgrade with empty channel URL unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^nix-termux: upgrade channel URL must not be empty$' "$tmp/upgrade-empty.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" upgrade-bootstrap "" >"$tmp/upgrade-bootstrap-empty.out" 2>"$tmp/upgrade-bootstrap-empty.err"; then
	printf '%s\n' "upgrade-bootstrap with empty manifest URL unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^nix-termux: upgrade-bootstrap manifest URL must not be empty$' "$tmp/upgrade-bootstrap-empty.err"

if PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" uninstall extra >"$tmp/uninstall-extra.out" 2>"$tmp/uninstall-extra.err"; then
	printf '%s\n' "uninstall with extra arguments unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^nix-termux: uninstall accepts no arguments$' "$tmp/uninstall-extra.err"
test -d "$tmp/home/.nix-termux"
test -x "$tmp/prefix/bin/nix-termux"

if HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	sh "$tmp/home/.nix-termux/share/installer/uninstall.sh" extra >"$tmp/uninstall-script-extra.out" 2>"$tmp/uninstall-script-extra.err"; then
	printf '%s\n' "direct uninstall script with extra arguments unexpectedly succeeded" >&2
	exit 1
fi
grep -q '^uninstall.sh: uninstall accepts no arguments$' "$tmp/uninstall-script-extra.err"
test -d "$tmp/home/.nix-termux"
test -x "$tmp/prefix/bin/nix-termux"

cat >"$tmp/prefix/bin/nix-env" <<EOF
#!$host_sh
printf '%s\n' user modified nix-env
EOF
chmod 755 "$tmp/prefix/bin/nix-env"

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" uninstall

[ ! -e "$tmp/prefix/bin/nix-termux" ]
[ -x "$tmp/prefix/bin/nix-hash" ]
grep -qx 'printf '\''%s\\n'\'' original nix-hash' "$tmp/prefix/bin/nix-hash"
[ -x "$tmp/prefix/bin/nix-env" ]
grep -Fqx "printf '%s\\n' user modified nix-env" "$tmp/prefix/bin/nix-env"
[ ! -e "$tmp/home/.nix-profile" ]
[ ! -d "$tmp/home/.nix-termux" ]

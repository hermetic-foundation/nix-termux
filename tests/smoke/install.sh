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
host_cat=$(command -v cat)
cp "$host_sh" "$tmp/prefix/bin/sh"
cat >"$tmp/prefix/bin/nix-hash" <<EOF
#!$host_sh
printf '%s\n' original nix-hash
EOF
chmod 755 "$tmp/prefix/bin/nix-hash"
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
if [ -x "\$NIX_TERMUX_STATE_DIR/nix/var/nix/profiles/default/bin/\$1" ]; then
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
	HOME="$tmp/no-channel-home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/no-channel-home/.nix-termux" \
	sh "$tmp/standalone/install.sh" 2>"$tmp/no-channel.err"; then
	printf '%s\n' "standalone install without channel unexpectedly succeeded" >&2
	exit 1
fi
grep -q 'runtime files not found; set NIX_TERMUX_CHANNEL_BASE_URL, NIX_TERMUX_CHANNEL_URL, or NIX_TERMUX_RUNTIME_ARCHIVE_URL' "$tmp/no-channel.err"

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
	NIX_TERMUX_RUNTIME_ARCHIVE_URL="file://$tmp/runtime.tar.gz" \
	NIX_TERMUX_RUNTIME_ARCHIVE_SHA256="$runtime_sha" \
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

grep -qx -- "-b" "$tmp/home/.nix-termux/proot.args"
grep -qx -- "$tmp/home/.nix-termux/tmp:/tmp" "$tmp/home/.nix-termux/proot.args"
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

printf '%s\n' "$doctor_json" | jq -e \
	--arg sha "$sha" \
	'.schemaVersion == 1
	and .ok == true
	and .termux.ok == true
	and .proot.ok == true
	and .store.ok == true
	and .nix.ok == true
	and .userProfile.ok == true
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

env_output=$(
	PATH="$tmp/fake-bin:$PATH" \
		HOME="$tmp/home" \
		PREFIX="$tmp/prefix" \
		NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
		NIX_PATH='' \
		"$tmp/prefix/bin/nix-termux" env
)
printf '%s\n' "$env_output" | grep -q "^XDG_CONFIG_HOME=$tmp/home/.config$"
printf '%s\n' "$env_output" | grep -q "^XDG_CACHE_HOME=$tmp/home/.cache$"
printf '%s\n' "$env_output" | grep -q "^XDG_DATA_HOME=$tmp/home/.local/share$"
printf '%s\n' "$env_output" | grep -q "^XDG_STATE_HOME=$tmp/home/.local/state$"
printf '%s\n' "$env_output" | grep -q '^PATH=/home/termux/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/termux/bin:/usr/bin:/bin$'
printf '%s\n' "$env_output" | grep -q '^NIX_REMOTE=local$'
printf '%s\n' "$env_output" | grep -q '^NIX_PATH=nixpkgs=flake:nixpkgs$'
printf '%s\n' "$env_output" | grep -q '^NIX_PROFILES=/nix/var/nix/profiles/default /nix/var/nix/profiles/per-user/termux/profile$'
printf '%s\n' "$env_output" | grep -q "^SSL_CERT_FILE=$tmp/home/.nix-termux/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt$"

PATH="$tmp/fake-bin:$PATH" \
	HOME="$tmp/home" \
	PREFIX="$tmp/prefix" \
	NIX_TERMUX_STATE_DIR="$tmp/home/.nix-termux" \
	"$tmp/prefix/bin/nix-termux" uninstall

[ ! -e "$tmp/prefix/bin/nix-termux" ]
[ -x "$tmp/prefix/bin/nix-hash" ]
grep -qx 'printf '\''%s\\n'\'' original nix-hash' "$tmp/prefix/bin/nix-hash"
[ ! -e "$tmp/home/.nix-profile" ]
[ ! -d "$tmp/home/.nix-termux" ]

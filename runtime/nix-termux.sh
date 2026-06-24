#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

version=${NIX_TERMUX_VERSION:-0.1.0}

die() {
	printf 'nix-termux: %s\n' "$*" >&2
	exit 1
}

info() {
	printf '%s\n' "$*"
}

state_dir=${NIX_TERMUX_STATE_DIR:-"$HOME/.nix-termux"}
store_dir=${NIX_TERMUX_STORE_DIR:-"$state_dir/nix"}
root_dir=${NIX_TERMUX_ROOT_DIR:-"$state_dir/root"}
tmp_dir=${NIX_TERMUX_TMP_DIR:-"$state_dir/tmp"}
profile_dir=${NIX_TERMUX_PROFILE_DIR:-"$store_dir/var/nix/profiles/default"}
user_profile_dir=${NIX_TERMUX_USER_PROFILE_DIR:-"$store_dir/var/nix/profiles/per-user/termux/profile"}
cert_file=${NIX_TERMUX_SSL_CERT_FILE:-"$profile_dir/etc/ssl/certs/ca-bundle.crt"}
nix_conf_file=${NIX_TERMUX_NIX_CONF:-"$root_dir/etc/nix/nix.conf"}
config_file=${NIX_TERMUX_CONFIG:-"$state_dir/etc/nix-termux.conf"}
activation_file=${NIX_TERMUX_ACTIVATION:-"$state_dir/etc/bootstrap-activation.conf"}
proot=${NIX_TERMUX_PROOT:-proot}
resolv_conf_file=${NIX_TERMUX_RESOLV_CONF:-"$root_dir/etc/resolv.conf"}
android_bind_dirs=${NIX_TERMUX_ANDROID_BIND_DIRS:-"/sdcard /storage"}
manage_home_profile=${NIX_TERMUX_MANAGE_HOME_PROFILE:-yes}
managed_profile_target=/nix/var/nix/profiles/per-user/termux/profile
wrapper_names="nix-termux nix nix-shell nix-env nix-store nix-build nix-channel nix-collect-garbage nix-copy-closure nix-hash nix-instantiate nix-prefetch-url"

termux_prefix=${PREFIX:-/data/data/com.termux/files/usr}
termux_home=${HOME:-/data/data/com.termux/files/home}
nix_path=${NIX_TERMUX_NIX_PATH:-${NIX_PATH:-nixpkgs=flake:nixpkgs}}
proot_path=/home/termux/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/termux/bin:/usr/bin:/bin
proot_default_shell=/nix/var/nix/profiles/default/bin/bash
proot_cert_file=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt

usage() {
	cat <<'EOF'
Usage: nix-termux <command> [args]

Commands:
  doctor [--json]     Check Termux/proot/bootstrap readiness.
  env                 Print runtime paths and environment.
  enter [-- cmd...]   Enter the proot-backed Nix environment.
  run <args...>       Run `nix run <args...>` inside the environment.
  exec <cmd> [args...] Run an arbitrary command inside the environment.
  smoke-test [args...] Run the installed Termux device smoke test.
  upgrade [channel-url]
                      Reinstall runtime/bootstrap from a channel manifest.
  upgrade-bootstrap [manifest-url]
                      Reinstall runtime/bootstrap from a manifest.
  uninstall           Remove wrappers and nix-termux state.
  version             Print the nix-termux runtime version.
  help                Show this help.
EOF
}

help_command() {
	[ "$#" -eq 0 ] || die "help accepts no arguments"
	usage
}

have() {
	command -v "$1" >/dev/null 2>&1
}

validate_manage_home_profile() {
	case $manage_home_profile in
	yes | no)
		;;
	*)
		die "NIX_TERMUX_MANAGE_HOME_PROFILE must be yes or no"
		;;
	esac
}

validate_state_dir() {
	case $state_dir in
	/ | . | ..)
		die "NIX_TERMUX_STATE_DIR must not be $state_dir"
		;;
	esac
}

is_termux() {
	[ -n "${PREFIX:-}" ] && [ -d "$termux_prefix" ] && [ -d "$termux_home" ]
}

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

doctor_status() {
	doctor_termux=false
	doctor_proot=false
	doctor_store=false
	doctor_nix=false
	doctor_user_profile=false
	doctor_home_profile=false
	doctor_nix_conf=false
	doctor_certs=false
	doctor_activation=false
	doctor_dns=false
	doctor_wrappers=false
	doctor_installed_runtime_version=
	doctor_channel_url=
	doctor_runtime_archive_sha256=
	doctor_bootstrap_manifest_url=
	doctor_missing_wrappers=
	doctor_activation_sha=
	doctor_home_profile_path=$termux_home/.nix-profile
	doctor_status=0

	if is_termux; then
		doctor_termux=true
	else
		doctor_status=1
	fi
	if have "$proot"; then
		doctor_proot=true
	else
		doctor_status=1
	fi
	if [ -d "$store_dir/store" ]; then
		doctor_store=true
	else
		doctor_status=1
	fi
	if [ -x "$profile_dir/bin/nix" ]; then
		doctor_nix=true
	else
		doctor_status=1
	fi
	if [ -d "$(dirname -- "$user_profile_dir")" ]; then
		doctor_user_profile=true
	else
		doctor_status=1
	fi
	if [ -L "$doctor_home_profile_path" ]; then
		[ "$(readlink "$doctor_home_profile_path")" = "$managed_profile_target" ] &&
			doctor_home_profile=true ||
			doctor_status=1
	elif [ -d "$doctor_home_profile_path" ]; then
		doctor_home_profile=true
	else
		doctor_status=1
	fi
	if [ -r "$nix_conf_file" ]; then
		doctor_nix_conf=true
	else
		doctor_status=1
	fi
	if [ -r "$cert_file" ]; then
		doctor_certs=true
	else
		doctor_status=1
	fi
	if [ -s "$resolv_conf_file" ]; then
		doctor_dns=true
	else
		doctor_status=1
	fi
	for name in $wrapper_names; do
		target=$termux_prefix/bin/$name
		if [ ! -x "$target" ] || ! grep -q '^# nix-termux managed wrapper$' "$target"; then
			doctor_missing_wrappers="${doctor_missing_wrappers}${doctor_missing_wrappers:+ }$name"
		fi
	done
	if [ -z "$doctor_missing_wrappers" ]; then
		doctor_wrappers=true
	else
		doctor_status=1
	fi
	if [ -r "$activation_file" ]; then
		activation_sha=$(config_value bootstrap_sha256 "$activation_file")
		if [ -n "$activation_sha" ]; then
			doctor_activation=true
			doctor_activation_sha=$activation_sha
		else
			doctor_status=1
		fi
	else
		doctor_status=1
	fi
	doctor_installed_runtime_version=$(config_value runtime_version "$config_file")
	doctor_channel_url=$(config_value channel_url "$config_file")
	doctor_runtime_archive_sha256=$(config_value runtime_archive_sha256 "$config_file")
	doctor_bootstrap_manifest_url=$(config_value bootstrap_manifest_url "$config_file")
}

doctor_text() {
	if [ -n "$doctor_installed_runtime_version" ]; then
		info "runtime: ok ($version, installed $doctor_installed_runtime_version)"
	else
		info "runtime: ok ($version)"
	fi
	if [ -r "$config_file" ]; then
		info "config: ok ($config_file)"
		[ -n "$doctor_channel_url" ] && info "channel: $doctor_channel_url"
		[ -n "$doctor_bootstrap_manifest_url" ] && info "bootstrap-manifest: $doctor_bootstrap_manifest_url"
	else
		info "config: missing ($config_file)"
	fi
	if [ "$doctor_termux" = true ]; then
		info "termux: ok ($termux_prefix)"
	else
		info "termux: not detected"
	fi
	if [ "$doctor_proot" = true ]; then
		info "proot: ok ($(command -v "$proot"))"
	else
		info "proot: missing"
	fi
	if [ "$doctor_store" = true ]; then
		info "store: ok ($store_dir/store)"
	else
		info "store: missing ($store_dir/store)"
	fi
	if [ "$doctor_nix" = true ]; then
		info "nix: ok ($profile_dir/bin/nix)"
	else
		info "nix: missing ($profile_dir/bin/nix)"
	fi
	if [ "$doctor_user_profile" = true ]; then
		info "user-profile: ok ($user_profile_dir)"
	else
		info "user-profile: missing ($user_profile_dir)"
	fi
	if [ "$doctor_home_profile" = true ]; then
		info "home-profile: ok ($doctor_home_profile_path)"
	else
		info "home-profile: missing ($doctor_home_profile_path)"
	fi
	if [ "$doctor_nix_conf" = true ]; then
		info "nix-conf: ok ($nix_conf_file)"
	else
		info "nix-conf: missing ($nix_conf_file)"
	fi
	if [ "$doctor_certs" = true ]; then
		info "certs: ok ($cert_file)"
	else
		info "certs: missing ($cert_file)"
	fi
	if [ "$doctor_dns" = true ]; then
		info "dns: ok ($resolv_conf_file)"
	else
		info "dns: missing ($resolv_conf_file)"
	fi
	if [ "$doctor_wrappers" = true ]; then
		info "wrappers: ok ($termux_prefix/bin)"
	else
		info "wrappers: missing or unmanaged ($doctor_missing_wrappers)"
	fi
	if [ "$doctor_activation" = true ]; then
		info "activation: ok ($doctor_activation_sha)"
	elif [ -r "$activation_file" ]; then
		info "activation: malformed ($activation_file)"
	else
		info "activation: missing ($activation_file)"
	fi
}

doctor_json() {
	cat <<EOF
{
  "schemaVersion": 1,
  "runtimeVersion": "$(json_escape "$version")",
  "installedRuntimeVersion": "$(json_escape "$doctor_installed_runtime_version")",
  "ok": $([ "$doctor_status" -eq 0 ] && printf true || printf false),
  "config": {
    "path": "$(json_escape "$config_file")",
    "channelUrl": "$(json_escape "$doctor_channel_url")",
    "runtimeArchiveSha256": "$(json_escape "$doctor_runtime_archive_sha256")",
    "bootstrapManifestUrl": "$(json_escape "$doctor_bootstrap_manifest_url")"
  },
  "termux": {
    "ok": $doctor_termux,
    "prefix": "$(json_escape "$termux_prefix")",
    "home": "$(json_escape "$termux_home")"
  },
  "proot": {
    "ok": $doctor_proot,
    "command": "$(json_escape "$proot")"
  },
  "store": {
    "ok": $doctor_store,
    "path": "$(json_escape "$store_dir/store")"
  },
  "nix": {
    "ok": $doctor_nix,
    "path": "$(json_escape "$profile_dir/bin/nix")"
  },
  "userProfile": {
    "ok": $doctor_user_profile,
    "path": "$(json_escape "$user_profile_dir")"
  },
  "homeProfile": {
    "ok": $doctor_home_profile,
    "path": "$(json_escape "$doctor_home_profile_path")"
  },
  "nixConf": {
    "ok": $doctor_nix_conf,
    "path": "$(json_escape "$nix_conf_file")"
  },
  "certs": {
    "ok": $doctor_certs,
    "path": "$(json_escape "$cert_file")"
  },
  "dns": {
    "ok": $doctor_dns,
    "path": "$(json_escape "$resolv_conf_file")"
  },
  "wrappers": {
    "ok": $doctor_wrappers,
    "directory": "$(json_escape "$termux_prefix/bin")",
    "missing": "$(json_escape "$doctor_missing_wrappers")"
  },
  "activation": {
    "ok": $doctor_activation,
    "path": "$(json_escape "$activation_file")",
    "bootstrapSha256": "$(json_escape "$doctor_activation_sha")"
  }
}
EOF
}

doctor() {
	format=text
	if [ "$#" -gt 0 ] && [ "$1" = "--json" ]; then
		format=json
		shift
	fi
	[ "$#" -eq 0 ] || die "doctor accepts only --json"

	doctor_status

	case $format in
	json) doctor_json ;;
	text) doctor_text ;;
	esac

	return "$doctor_status"
}

print_env() {
	[ "$#" -eq 0 ] || die "env accepts no arguments"

	cat <<EOF
NIX_TERMUX_STATE_DIR=$state_dir
NIX_TERMUX_VERSION=$version
NIX_TERMUX_STORE_DIR=$store_dir
NIX_TERMUX_ROOT_DIR=$root_dir
NIX_TERMUX_TMP_DIR=$tmp_dir
NIX_TERMUX_PROFILE_DIR=$profile_dir
NIX_TERMUX_USER_PROFILE_DIR=$user_profile_dir
NIX_TERMUX_SSL_CERT_FILE=$cert_file
NIX_TERMUX_NIX_CONF=$nix_conf_file
NIX_TERMUX_CONFIG=$config_file
NIX_TERMUX_ACTIVATION=$activation_file
NIX_TERMUX_PROOT=$proot
NIX_TERMUX_RESOLV_CONF=$resolv_conf_file
NIX_TERMUX_ANDROID_BIND_DIRS=$android_bind_dirs
PREFIX=$termux_prefix
HOME=$termux_home
XDG_CACHE_HOME=$termux_home/.cache
XDG_CONFIG_HOME=$termux_home/.config
XDG_DATA_HOME=$termux_home/.local/share
XDG_STATE_HOME=$termux_home/.local/state
PATH=$proot_path
NIX_CONF_DIR=/etc/nix
NIX_REMOTE=local
NIX_PATH=$nix_path
NIX_PROFILES=/nix/var/nix/profiles/default /nix/var/nix/profiles/per-user/termux/profile
SHELL=$proot_default_shell
NIX_SSL_CERT_FILE=$proot_cert_file
SSL_CERT_FILE=$proot_cert_file
EOF
}

config_value() {
	key=$1
	file=$2

	[ -r "$file" ] || return 0
	sed -n 's/^'"$key"'=\(.*\)$/\1/p' "$file" | head -n 1
}

write_resolv_conf() {
	target=$1
	source=

	mkdir -p "$(dirname -- "$target")"

	if [ -r "$termux_prefix/etc/resolv.conf" ] && [ -s "$termux_prefix/etc/resolv.conf" ]; then
		source=$termux_prefix/etc/resolv.conf
	elif [ -r /etc/resolv.conf ] && [ -s /etc/resolv.conf ]; then
		source=/etc/resolv.conf
	fi

	if [ -n "$source" ]; then
		cp "$source" "$target"
		return
	fi

	: >"$target"
	if have getprop; then
		for prop in net.dns1 net.dns2 net.dns3 net.dns4; do
			value=$(getprop "$prop" 2>/dev/null || true)
			case $value in
			"" | *[!0-9a-fA-F:.]*)
				;;
			*)
				printf 'nameserver %s\n' "$value" >>"$target"
				;;
			esac
		done
	fi

	if [ ! -s "$target" ]; then
		rm -f "$target"
		return 1
	fi
}

optional_android_binds() {
	for bind_dir in $android_bind_dirs; do
		case $bind_dir in
		/*)
			;;
		*)
			continue
			;;
		esac
		[ -e "$bind_dir" ] || continue
		printf '%s\n%s\n' -b "$bind_dir:$bind_dir"
	done
}

enter() {
	[ -d "$store_dir" ] || die "state not initialized at $state_dir; run installer first"
	have "$proot" || die "proot is required; install it with: pkg install proot"
	validate_manage_home_profile
	mkdir -p "$tmp_dir" "$root_dir/home" "$root_dir/root" "$root_dir/tmp" "$store_dir/var/nix/profiles/per-user/root" "$store_dir/var/nix/profiles/per-user/termux"
	mkdir -p "$termux_home/.cache" "$termux_home/.config" "$termux_home/.local/share" "$termux_home/.local/state"
	if [ "$manage_home_profile" = yes ] && [ ! -e "$termux_home/.nix-profile" ] && [ ! -L "$termux_home/.nix-profile" ]; then
		ln -s /nix/var/nix/profiles/per-user/termux/profile "$termux_home/.nix-profile"
	fi
	write_resolv_conf "$resolv_conf_file" || die "could not create $resolv_conf_file; set NIX_TERMUX_RESOLV_CONF to a readable resolver config"

	shell=${NIX_TERMUX_SHELL:-$proot_default_shell}
	if [ "$shell" = "$proot_default_shell" ] && [ ! -x "$profile_dir/bin/bash" ]; then
		shell=/bin/sh
	fi

	if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
		shift
	fi

	if [ "$#" -eq 0 ]; then
		set -- "$shell" -l
	fi

	# shellcheck disable=SC2046
	exec "$proot" \
		--link2symlink \
		-0 \
		-r "$root_dir" \
		-b "$store_dir:/nix" \
		-b "$tmp_dir:/tmp" \
		-b "$termux_home:/home/termux" \
		-b "$termux_prefix:/termux" \
		-b /dev \
		-b /proc \
		-b /sys \
		$(optional_android_binds) \
		-w /home/termux \
		/usr/bin/env \
		HOME=/home/termux \
		TERM="${TERM:-xterm-256color}" \
		TMPDIR=/tmp \
		USER=termux \
		LOGNAME=termux \
		SHELL="$shell" \
		XDG_CACHE_HOME=/home/termux/.cache \
		XDG_CONFIG_HOME=/home/termux/.config \
		XDG_DATA_HOME=/home/termux/.local/share \
		XDG_STATE_HOME=/home/termux/.local/state \
		PATH="$proot_path" \
		NIX_CONF_DIR=/etc/nix \
		NIX_REMOTE=local \
		NIX_PATH="$nix_path" \
		NIX_PROFILES="/nix/var/nix/profiles/default /nix/var/nix/profiles/per-user/termux/profile" \
		NIX_SSL_CERT_FILE="$proot_cert_file" \
		SSL_CERT_FILE="$proot_cert_file" \
		"$@"
}

run_nix() {
	[ "$#" -gt 0 ] || die "run requires nix arguments"
	enter -- nix run "$@"
}

version() {
	[ "$#" -eq 0 ] || die "version accepts no arguments"
	printf '%s\n' "$version"
}

exec_command() {
	[ "$#" -gt 0 ] || die "exec requires a command"
	enter -- "$@"
}

smoke_test() {
	smoke_script=${NIX_TERMUX_DEVICE_SMOKE:-"$state_dir/share/tests/device-smoke.sh"}
	[ -x "$smoke_script" ] || die "device smoke test not found at $smoke_script"
	exec sh "$smoke_script" "$@"
}

upgrade() {
	channel=${1:-}
	install_script=${NIX_TERMUX_INSTALL:-"$state_dir/share/installer/install.sh"}

	[ "$#" -le 1 ] || die "upgrade accepts at most one channel URL"
	if [ "$#" -eq 1 ] && [ -z "$1" ]; then
		die "upgrade channel URL must not be empty"
	fi
	[ -x "$install_script" ] || die "install script not found at $install_script"

	if [ -z "$channel" ]; then
		channel=$(config_value channel_url "$config_file")
	fi
	[ -n "$channel" ] || die "no channel URL supplied and none saved in $config_file"

	NIX_TERMUX_CHANNEL_URL=$channel \
		NIX_TERMUX_STATE_DIR=$state_dir \
		PREFIX=$termux_prefix \
		HOME=$termux_home \
		exec sh "$install_script"
}

uninstall() {
	uninstall_script=${NIX_TERMUX_UNINSTALL:-"$state_dir/share/installer/uninstall.sh"}
	[ "$#" -eq 0 ] || die "uninstall accepts no arguments"
	[ -x "$uninstall_script" ] || die "uninstall script not found at $uninstall_script"
	exec sh "$uninstall_script"
}

upgrade_bootstrap() {
	manifest_url=${1:-}
	install_script=${NIX_TERMUX_INSTALL:-"$state_dir/share/installer/install.sh"}

	[ "$#" -le 1 ] || die "upgrade-bootstrap accepts at most one manifest URL"
	if [ "$#" -eq 1 ] && [ -z "$1" ]; then
		die "upgrade-bootstrap manifest URL must not be empty"
	fi
	[ -x "$install_script" ] || die "install script not found at $install_script"

	if [ -z "$manifest_url" ]; then
		manifest_url=$(config_value bootstrap_manifest_url "$config_file")
	fi
	[ -n "$manifest_url" ] || die "no manifest URL supplied and none saved in $config_file"

	NIX_TERMUX_BOOTSTRAP_MANIFEST_URL=$manifest_url \
		NIX_TERMUX_STATE_DIR=$state_dir \
		PREFIX=$termux_prefix \
		HOME=$termux_home \
		exec sh "$install_script"
}

cmd=${1:-help}
if [ "$#" -gt 0 ]; then
	shift
fi

validate_state_dir

case "$cmd" in
doctor) doctor "$@" ;;
env) print_env "$@" ;;
enter) enter "$@" ;;
run) run_nix "$@" ;;
exec) exec_command "$@" ;;
smoke-test) smoke_test "$@" ;;
upgrade) upgrade "$@" ;;
upgrade-bootstrap) upgrade_bootstrap "$@" ;;
uninstall) uninstall "$@" ;;
version | -V | --version) version "$@" ;;
help | -h | --help) help_command "$@" ;;
*) die "unknown command: $cmd" ;;
esac

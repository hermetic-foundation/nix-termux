#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

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
cert_file=${NIX_TERMUX_SSL_CERT_FILE:-"$profile_dir/etc/ssl/certs/ca-bundle.crt"}
nix_conf_file=${NIX_TERMUX_NIX_CONF:-"$root_dir/etc/nix/nix.conf"}
config_file=${NIX_TERMUX_CONFIG:-"$state_dir/etc/nix-termux.conf"}
activation_file=${NIX_TERMUX_ACTIVATION:-"$state_dir/etc/bootstrap-activation.conf"}
proot=${NIX_TERMUX_PROOT:-proot}
resolv_conf_file=${NIX_TERMUX_RESOLV_CONF:-"$root_dir/etc/resolv.conf"}
wrapper_names="nix-termux nix nix-shell nix-env nix-store nix-build nix-channel nix-collect-garbage nix-copy-closure nix-hash nix-instantiate nix-prefetch-url"

termux_prefix=${PREFIX:-/data/data/com.termux/files/usr}
termux_home=${HOME:-/data/data/com.termux/files/home}

usage() {
	cat <<'EOF'
Usage: nix-termux <command> [args]

Commands:
  doctor [--json]     Check Termux/proot/bootstrap readiness.
  env                 Print runtime paths and environment.
  enter [-- cmd...]   Enter the proot-backed Nix environment.
  run <args...>       Run `nix run <args...>` inside the environment.
  exec <cmd> [args...] Run an arbitrary command inside the environment.
  upgrade-bootstrap [manifest-url]
                      Reinstall runtime/bootstrap from a manifest.
  uninstall           Remove wrappers and nix-termux state.
  help                Show this help.
EOF
}

have() {
	command -v "$1" >/dev/null 2>&1
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
	doctor_nix_conf=false
	doctor_certs=false
	doctor_activation=false
	doctor_dns=false
	doctor_wrappers=false
	doctor_missing_wrappers=
	doctor_activation_sha=
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
		if [ ! -x "$target" ] || ! grep -q 'nix-termux' "$target"; then
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
}

doctor_text() {
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
  "ok": $([ "$doctor_status" -eq 0 ] && printf true || printf false),
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
	cat <<EOF
NIX_TERMUX_STATE_DIR=$state_dir
NIX_TERMUX_STORE_DIR=$store_dir
NIX_TERMUX_ROOT_DIR=$root_dir
NIX_TERMUX_TMP_DIR=$tmp_dir
NIX_TERMUX_PROFILE_DIR=$profile_dir
NIX_TERMUX_SSL_CERT_FILE=$cert_file
NIX_TERMUX_NIX_CONF=$nix_conf_file
NIX_TERMUX_CONFIG=$config_file
NIX_TERMUX_ACTIVATION=$activation_file
NIX_TERMUX_PROOT=$proot
NIX_TERMUX_RESOLV_CONF=$resolv_conf_file
PREFIX=$termux_prefix
HOME=$termux_home
XDG_CACHE_HOME=$termux_home/.cache
XDG_CONFIG_HOME=$termux_home/.config
XDG_DATA_HOME=$termux_home/.local/share
XDG_STATE_HOME=$termux_home/.local/state
NIX_REMOTE=local
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

enter() {
	[ -d "$store_dir" ] || die "state not initialized at $state_dir; run installer first"
	have "$proot" || die "proot is required; install it with: pkg install proot"
	mkdir -p "$tmp_dir" "$root_dir/home" "$root_dir/root" "$root_dir/tmp" "$store_dir/var/nix/profiles/per-user/root" "$store_dir/var/nix/profiles/per-user/termux"
	mkdir -p "$termux_home/.cache" "$termux_home/.config" "$termux_home/.local/share" "$termux_home/.local/state"
	write_resolv_conf "$resolv_conf_file" || die "could not create $resolv_conf_file; set NIX_TERMUX_RESOLV_CONF to a readable resolver config"

	shell=${NIX_TERMUX_SHELL:-"$profile_dir/bin/bash"}
	[ -x "$shell" ] || shell=/bin/sh

	if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
		shift
	fi

	if [ "$#" -eq 0 ]; then
		set -- "$shell" -l
	fi

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
		-w /home/termux \
		/usr/bin/env \
		HOME=/home/termux \
		TERM="${TERM:-xterm-256color}" \
		TMPDIR=/tmp \
		USER=termux \
		LOGNAME=termux \
		XDG_CACHE_HOME=/home/termux/.cache \
		XDG_CONFIG_HOME=/home/termux/.config \
		XDG_DATA_HOME=/home/termux/.local/share \
		XDG_STATE_HOME=/home/termux/.local/state \
		PATH="/nix/var/nix/profiles/default/bin:/termux/bin:/usr/bin:/bin" \
		NIX_CONF_DIR=/etc/nix \
		NIX_REMOTE=local \
		NIX_SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt \
		"$@"
}

run_nix() {
	[ "$#" -gt 0 ] || die "run requires nix arguments"
	enter -- nix run "$@"
}

exec_command() {
	[ "$#" -gt 0 ] || die "exec requires a command"
	enter -- "$@"
}

uninstall() {
	uninstall_script=${NIX_TERMUX_UNINSTALL:-"$state_dir/share/installer/uninstall.sh"}
	[ -x "$uninstall_script" ] || die "uninstall script not found at $uninstall_script"
	exec sh "$uninstall_script"
}

upgrade_bootstrap() {
	manifest_url=${1:-}
	install_script=${NIX_TERMUX_INSTALL:-"$state_dir/share/installer/install.sh"}

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

case "$cmd" in
doctor) doctor "$@" ;;
env) print_env "$@" ;;
enter) enter "$@" ;;
run) run_nix "$@" ;;
exec) exec_command "$@" ;;
upgrade-bootstrap) upgrade_bootstrap "$@" ;;
uninstall) uninstall "$@" ;;
help | -h | --help) usage ;;
*) die "unknown command: $cmd" ;;
esac

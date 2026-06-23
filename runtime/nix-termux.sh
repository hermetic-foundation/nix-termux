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
profile_dir=${NIX_TERMUX_PROFILE_DIR:-"$store_dir/var/nix/profiles/default"}
proot=${NIX_TERMUX_PROOT:-proot}

termux_prefix=${PREFIX:-/data/data/com.termux/files/usr}
termux_home=${HOME:-/data/data/com.termux/files/home}

usage() {
	cat <<'EOF'
Usage: nix-termux <command> [args]

Commands:
  doctor              Check Termux/proot/bootstrap readiness.
  env                 Print runtime paths and environment.
  enter [-- cmd...]   Enter the proot-backed Nix environment.
  run <args...>       Run `nix run <args...>` inside the environment.
  exec <cmd> [args...] Run an arbitrary command inside the environment.
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

doctor() {
	status=0

	if is_termux; then
		info "termux: ok ($termux_prefix)"
	else
		info "termux: not detected"
		status=1
	fi

	if have "$proot"; then
		info "proot: ok ($(command -v "$proot"))"
	else
		info "proot: missing"
		status=1
	fi

	if [ -d "$store_dir/store" ]; then
		info "store: ok ($store_dir/store)"
	else
		info "store: missing ($store_dir/store)"
		status=1
	fi

	if [ -x "$profile_dir/bin/nix" ]; then
		info "nix: ok ($profile_dir/bin/nix)"
	else
		info "nix: missing ($profile_dir/bin/nix)"
		status=1
	fi

	return "$status"
}

print_env() {
	cat <<EOF
NIX_TERMUX_STATE_DIR=$state_dir
NIX_TERMUX_STORE_DIR=$store_dir
NIX_TERMUX_ROOT_DIR=$root_dir
NIX_TERMUX_PROFILE_DIR=$profile_dir
NIX_TERMUX_PROOT=$proot
PREFIX=$termux_prefix
HOME=$termux_home
EOF
}

enter() {
	[ -d "$store_dir" ] || die "state not initialized at $state_dir; run installer first"
	have "$proot" || die "proot is required; install it with: pkg install proot"

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
		-b "$termux_home:/home/termux" \
		-b "$termux_prefix:/termux" \
		-b /dev \
		-b /proc \
		-b /sys \
		-w /home/termux \
		/usr/bin/env \
		HOME=/home/termux \
		TERM="${TERM:-xterm-256color}" \
		USER=termux \
		LOGNAME=termux \
		PATH="/nix/var/nix/profiles/default/bin:/termux/bin:/usr/bin:/bin" \
		NIX_SSL_CERT_FILE=/termux/etc/tls/cert.pem \
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
uninstall) uninstall "$@" ;;
help | -h | --help) usage ;;
*) die "unknown command: $cmd" ;;
esac

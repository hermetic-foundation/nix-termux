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
runtime_version=${NIX_TERMUX_VERSION:-}
prefix=${PREFIX:-}
termux_arch=${NIX_TERMUX_ARCH:-}
channel_url=${NIX_TERMUX_CHANNEL_URL:-}
channel_base_url=${NIX_TERMUX_CHANNEL_BASE_URL:-}
runtime_archive_url=${NIX_TERMUX_RUNTIME_ARCHIVE_URL:-}
runtime_archive_sha256=${NIX_TERMUX_RUNTIME_ARCHIVE_SHA256:-}
bootstrap_manifest_url=${NIX_TERMUX_BOOTSTRAP_MANIFEST_URL:-}
bootstrap_url=${NIX_TERMUX_BOOTSTRAP_URL:-}
bootstrap_sha256=${NIX_TERMUX_BOOTSTRAP_SHA256:-}
bootstrap_archive_ready=no
wrapper_names="nix-termux nix nix-shell nix-env nix-store nix-build nix-channel nix-collect-garbage nix-copy-closure nix-hash nix-instantiate nix-prefetch-url"
managed_profile_target=/nix/var/nix/profiles/per-user/termux/profile
runtime_archive=$state_dir/tmp/runtime.tar.gz
runtime_source=$state_dir/tmp/runtime-source
bootstrap_archive=$state_dir/tmp/bootstrap.tar.gz
bootstrap_stage=$state_dir/tmp/bootstrap-stage

cleanup_temp() {
	rm -f "$runtime_archive" "$bootstrap_archive"
	rm -rf "$runtime_source" "$bootstrap_stage"
}
trap cleanup_temp EXIT INT TERM

[ -n "$prefix" ] || die "PREFIX is not set; run this from stock Termux"
[ -d "$prefix/bin" ] || die "Termux prefix bin directory not found: $prefix/bin"

for command in mkdir chmod cp ln mv rm; do
	have "$command" || die "required command missing: $command"
done
for command in basename dirname grep head sed uname; do
	have "$command" || die "required command missing: $command"
done

if ! have proot; then
	die "proot is required; install it with: pkg install proot"
fi

fetch_url() {
	url=$1
	output=$2

	case $url in
	file://*)
		cp "${url#file://}" "$output"
		;;
	/*)
		cp "$url" "$output"
		;;
	*)
		have curl || die "curl is required to fetch $url"
		curl -fL "$url" -o "$output" ||
			die "failed to fetch $url"
		;;
	esac
}

validate_tar_paths() {
	archive=$1
	label=$2
	listing=$state_dir/tmp/tar-list.$$
	unsafe_member=

	rm -f "$listing"
	tar -tzf "$archive" >"$listing" ||
		die "$label archive could not be listed"

	while IFS= read -r member; do
		case $member in
		"" | /* | .. | ../* | */.. | */../*)
			unsafe_member=$member
			break
			;;
		esac
	done <"$listing"
	rm -f "$listing"

	[ -z "$unsafe_member" ] ||
		die "$label archive contains unsafe path: $unsafe_member"
}

validate_bootstrap_stage() {
	stage=$1

	path_exists() {
		[ -e "$1" ] || [ -L "$1" ]
	}

	[ -d "$stage/nix/store" ] || die "bootstrap archive missing nix/store"
	path_exists "$stage/nix/var/nix/profiles/default/bin/nix" ||
		die "bootstrap archive missing nix/var/nix/profiles/default/bin/nix"
	path_exists "$stage/nix/var/nix/profiles/default/bin/nix-store" ||
		die "bootstrap archive missing nix/var/nix/profiles/default/bin/nix-store"
	path_exists "$stage/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt" ||
		die "bootstrap archive missing nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
	[ -r "$stage/root/etc/nix/nix.conf" ] ||
		die "bootstrap archive missing root/etc/nix/nix.conf"
	path_exists "$stage/root/usr/bin/env" ||
		die "bootstrap archive missing root/usr/bin/env"
	path_exists "$stage/root/bin/sh" ||
		die "bootstrap archive missing root/bin/sh"
	[ -r "$stage/root/etc/passwd" ] ||
		die "bootstrap archive missing root/etc/passwd"
	[ -r "$stage/root/etc/group" ] ||
		die "bootstrap archive missing root/etc/group"
	[ -r "$stage/root/etc/nsswitch.conf" ] ||
		die "bootstrap archive missing root/etc/nsswitch.conf"
	grep -q '^termux:' "$stage/root/etc/passwd" ||
		die "bootstrap archive root/etc/passwd missing termux user"
	grep -q '^termux:' "$stage/root/etc/group" ||
		die "bootstrap archive root/etc/group missing termux group"
	[ -r "$stage/nix-termux/bootstrap.registration" ] ||
		die "bootstrap archive missing nix-termux/bootstrap.registration"
}

json_string_value() {
	key=$1
	file=$2

	sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1
}

json_string_value_n() {
	key=$1
	index=$2
	file=$3

	sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | sed -n "${index}p"
}

json_path_string() {
	path=$1
	file=$2

	if have jq; then
		jq -er "$path // empty" "$file" 2>/dev/null || true
		return
	fi

	case $path in
	.archive.url | .runtime.url)
		json_string_value_n url 1 "$file"
		;;
	.bootstrapManifest.url)
		json_string_value_n url 2 "$file"
		;;
	.archive.sha256 | .runtime.sha256)
		json_string_value sha256 "$file"
		;;
	.platform.termuxArch)
		json_string_value termuxArch "$file"
		;;
	*)
		return 1
		;;
	esac
}

resolve_manifest_url() {
	base=$1
	value=$2

	case $value in
	*://*)
		printf '%s\n' "$value"
		;;
	/*)
		printf '%s\n' "$value"
		;;
	*)
		case $base in
		file://*)
			base_path=${base#file://}
			case $base_path in
			*/) printf 'file://%s%s\n' "$base_path" "$value" ;;
			*) printf 'file://%s/%s\n' "$(dirname -- "$base_path")" "$value" ;;
			esac
			;;
		*://*)
			printf '%s/%s\n' "${base%/*}" "$value"
			;;
		*)
			printf '%s\n' "$value"
			;;
		esac
		;;
	esac
}

detect_arch() {
	if [ -n "$termux_arch" ]; then
		printf '%s\n' "$termux_arch"
		return
	fi

	if have pkg; then
		pkg_arch=$(pkg --print-architecture 2>/dev/null || true)
		if [ -n "$pkg_arch" ]; then
			printf '%s\n' "$pkg_arch"
			return
		fi
	fi

	uname_arch=$(uname -m 2>/dev/null || true)
	case $uname_arch in
	aarch64 | arm64) printf '%s\n' aarch64 ;;
	armv7* | armv8l) printf '%s\n' arm ;;
	i686 | i386) printf '%s\n' i686 ;;
	x86_64 | amd64) printf '%s\n' x86_64 ;;
	*) die "could not detect Termux architecture; set NIX_TERMUX_ARCH" ;;
	esac
}

load_manifest() {
	manifest=$1

	if [ -z "$termux_arch" ]; then
		termux_arch=$(detect_arch)
	fi

	grep -Eq '"schemaVersion"[[:space:]]*:[[:space:]]*1([,[:space:]}]|$)' "$manifest" ||
		die "unsupported bootstrap manifest schemaVersion"
	grep -Eq '"storeDir"[[:space:]]*:[[:space:]]*"nix"' "$manifest" ||
		die "unsupported bootstrap manifest storeDir"
	grep -Eq '"rootDir"[[:space:]]*:[[:space:]]*"root"' "$manifest" ||
		die "unsupported bootstrap manifest rootDir"
	grep -Eq '"nixBin"[[:space:]]*:[[:space:]]*"nix/var/nix/profiles/default/bin/nix"' "$manifest" ||
		die "unsupported bootstrap manifest nixBin"
	if grep -Eq '"registration"' "$manifest"; then
		grep -Eq '"registration"[[:space:]]*:[[:space:]]*"nix-termux/bootstrap.registration"' "$manifest" ||
			die "unsupported bootstrap manifest registration"
	fi

	manifest_archive_url=$(json_path_string .archive.url "$manifest")
	manifest_sha256=$(json_path_string .archive.sha256 "$manifest")
	manifest_termux_arch=$(json_path_string .platform.termuxArch "$manifest")
	[ -n "$manifest_archive_url" ] || die "bootstrap manifest missing archive.url"
	[ -n "$manifest_sha256" ] || die "bootstrap manifest missing archive.sha256"
	[ -n "$manifest_termux_arch" ] || die "bootstrap manifest missing platform.termuxArch"
	[ "$manifest_termux_arch" = "$termux_arch" ] ||
		die "bootstrap manifest architecture mismatch: expected $termux_arch got $manifest_termux_arch"

	bootstrap_url=${bootstrap_url:-"$(resolve_manifest_url "$bootstrap_manifest_url" "$manifest_archive_url")"}
	bootstrap_sha256=${bootstrap_sha256:-"$manifest_sha256"}
}

load_channel() {
	channel=$1

	if [ -z "$termux_arch" ]; then
		termux_arch=$(detect_arch)
	fi

	grep -Eq '"schemaVersion"[[:space:]]*:[[:space:]]*1([,[:space:]}]|$)' "$channel" ||
		die "unsupported channel manifest schemaVersion"
	grep -Eq '"runtime"[[:space:]]*:' "$channel" ||
		die "channel manifest missing runtime"
	grep -Eq '"bootstrapManifest"[[:space:]]*:' "$channel" ||
		die "channel manifest missing bootstrapManifest"

	channel_runtime_url=$(json_path_string .runtime.url "$channel")
	channel_bootstrap_manifest_url=$(json_path_string .bootstrapManifest.url "$channel")
	channel_runtime_sha256=$(json_path_string .runtime.sha256 "$channel")
	channel_termux_arch=$(json_path_string .platform.termuxArch "$channel")

	[ -n "$channel_runtime_url" ] || die "channel manifest missing runtime.url"
	[ -n "$channel_runtime_sha256" ] || die "channel manifest missing runtime.sha256"
	[ -n "$channel_bootstrap_manifest_url" ] || die "channel manifest missing bootstrapManifest.url"
	[ -n "$channel_termux_arch" ] || die "channel manifest missing platform.termuxArch"
	[ "$channel_termux_arch" = "$termux_arch" ] ||
		die "channel manifest architecture mismatch: expected $termux_arch got $channel_termux_arch"

	runtime_archive_url=${runtime_archive_url:-"$(resolve_manifest_url "$channel_url" "$channel_runtime_url")"}
	runtime_archive_sha256=${runtime_archive_sha256:-"$channel_runtime_sha256"}
	bootstrap_manifest_url=${bootstrap_manifest_url:-"$(resolve_manifest_url "$channel_url" "$channel_bootstrap_manifest_url")"}
}

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

mkdir -p "$state_dir/tmp"

if [ -z "$channel_url" ] && [ -n "$channel_base_url" ]; then
	termux_arch=$(detect_arch)
	channel_url=$(resolve_manifest_url "$channel_base_url/" "nix-termux-channel-$termux_arch.json")
fi

if [ -n "$channel_url" ]; then
	channel=$state_dir/tmp/channel.json
	fetch_url "$channel_url" "$channel"
	load_channel "$channel"
fi

if [ -f "$source_root/bin/nix-termux" ]; then
	source_bin=$source_root/bin/nix-termux
	source_install=$source_root/installer/install.sh
	source_runtime=$source_root/runtime/nix-termux.sh
	source_uninstall=$source_root/installer/uninstall.sh
	source_device_smoke=$source_root/tests/termux/device-smoke.sh
else
	source_bin=$state_dir/bin/nix-termux
	source_install=$state_dir/share/installer/install.sh
	source_runtime=$state_dir/runtime/nix-termux.sh
	source_uninstall=$state_dir/share/installer/uninstall.sh
	source_device_smoke=$state_dir/share/tests/device-smoke.sh

	if [ -n "$runtime_archive_url" ]; then
		have tar || die "tar is required to unpack NIX_TERMUX_RUNTIME_ARCHIVE_URL"

		rm -rf "$runtime_source"
		mkdir -p "$runtime_source"
		fetch_url "$runtime_archive_url" "$runtime_archive"

		if [ -n "$runtime_archive_sha256" ]; then
			have sha256sum || die "sha256sum is required when NIX_TERMUX_RUNTIME_ARCHIVE_SHA256 is set"
			actual=$(sha256sum "$runtime_archive")
			actual=${actual%% *}
			[ "$actual" = "$runtime_archive_sha256" ] || die "runtime archive sha256 mismatch: expected $runtime_archive_sha256 got $actual"
		fi

		validate_tar_paths "$runtime_archive" runtime
		tar -xzf "$runtime_archive" -C "$runtime_source"
		rm -f "$runtime_archive"

		source_bin=$runtime_source/bin/nix-termux
		source_install=$runtime_source/installer/install.sh
		source_runtime=$runtime_source/runtime/nix-termux.sh
		source_uninstall=$runtime_source/installer/uninstall.sh
		source_device_smoke=$runtime_source/tests/termux/device-smoke.sh
	fi
fi

validate_runtime_sources() {
	[ -r "$source_bin" ] ||
		die "runtime files not found; set NIX_TERMUX_CHANNEL_BASE_URL, NIX_TERMUX_CHANNEL_URL, or NIX_TERMUX_RUNTIME_ARCHIVE_URL"
	[ -r "$source_install" ] || die "runtime archive missing installer/install.sh"
	[ -r "$source_runtime" ] || die "runtime archive missing runtime/nix-termux.sh"
	[ -r "$source_uninstall" ] || die "runtime archive missing installer/uninstall.sh"
	[ -r "$source_device_smoke" ] || die "runtime archive missing tests/termux/device-smoke.sh"
}

validate_runtime_sources
# shellcheck disable=SC2016
runtime_version=$(sed -n 's/^version=${NIX_TERMUX_VERSION:-\([^}]*\)}$/\1/p' "$source_runtime" | head -n 1)
runtime_version=${runtime_version:-${NIX_TERMUX_VERSION:-0.1.0}}

install_file() {
	source=$1
	target=$2
	target_dir=$(dirname -- "$target")
	target_tmp=$target_dir/.install.$(basename -- "$target").$$

	[ -r "$source" ] || die "source file not found: $source"
	if [ "$source" != "$target" ]; then
		rm -f "$target_tmp"
		cp "$source" "$target_tmp"
		mv -f "$target_tmp" "$target"
	fi
}

write_file() {
	target=$1
	target_dir=$(dirname -- "$target")
	target_tmp=$target_dir/.install.$(basename -- "$target").$$

	rm -f "$target_tmp"
	cat >"$target_tmp"
	mv -f "$target_tmp" "$target"
}

is_managed_wrapper() {
	target=$1

	[ -f "$target" ] || return 1
	grep -q '^# nix-termux managed wrapper$' "$target"
}

backup_prefix_command() {
	name=$1
	target=$prefix/bin/$name
	backup=$state_dir/share/prefix-backup/$name

	[ -e "$target" ] || return 0
	is_managed_wrapper "$target" && return 0
	[ -e "$backup" ] && return 0

	cp -p "$target" "$backup"
}

mkdir -p "$state_dir/bin" "$state_dir/etc" "$state_dir/runtime" "$state_dir/share/installer" "$state_dir/share/prefix-backup" "$state_dir/share/tests" "$state_dir/root/usr/bin" "$state_dir/root/home" "$state_dir/root/tmp" "$state_dir/tmp" "$state_dir/nix"
mkdir -p \
	"$state_dir/nix/store" \
	"$state_dir/nix/var/log/nix/drvs" \
	"$state_dir/nix/var/nix/db" \
	"$state_dir/nix/var/nix/gcroots/auto" \
	"$state_dir/nix/var/nix/profiles/per-user/root" \
	"$state_dir/nix/var/nix/profiles/per-user/termux" \
	"$state_dir/nix/var/nix/temproots"

if [ ! -e "$HOME/.nix-profile" ] && [ ! -L "$HOME/.nix-profile" ]; then
	ln -s "$managed_profile_target" "$HOME/.nix-profile"
fi

if [ -n "$bootstrap_manifest_url" ]; then
	manifest=$state_dir/bootstrap-manifest.json
	fetch_url "$bootstrap_manifest_url" "$manifest"
	load_manifest "$manifest"
fi

if [ -n "$bootstrap_url" ]; then
	have tar || die "tar is required to unpack NIX_TERMUX_BOOTSTRAP_URL"

	fetch_url "$bootstrap_url" "$bootstrap_archive"

	if [ -n "$bootstrap_sha256" ]; then
		have sha256sum || die "sha256sum is required when NIX_TERMUX_BOOTSTRAP_SHA256 is set"
		actual=$(sha256sum "$bootstrap_archive")
		actual=${actual%% *}
		[ "$actual" = "$bootstrap_sha256" ] || die "bootstrap sha256 mismatch: expected $bootstrap_sha256 got $actual"
	fi

	validate_tar_paths "$bootstrap_archive" bootstrap
	rm -rf "$bootstrap_stage"
	mkdir -p "$bootstrap_stage"
	tar -xzf "$bootstrap_archive" -C "$bootstrap_stage"
	validate_bootstrap_stage "$bootstrap_stage"
	bootstrap_archive_ready=yes
fi

install_file "$source_bin" "$state_dir/bin/nix-termux"
install_file "$source_install" "$state_dir/share/installer/install.sh"
install_file "$source_runtime" "$state_dir/runtime/nix-termux.sh"
install_file "$source_uninstall" "$state_dir/share/installer/uninstall.sh"
install_file "$source_device_smoke" "$state_dir/share/tests/device-smoke.sh"
chmod 755 "$state_dir/bin/nix-termux" "$state_dir/share/installer/install.sh" "$state_dir/runtime/nix-termux.sh" "$state_dir/share/installer/uninstall.sh" "$state_dir/share/tests/device-smoke.sh"

if [ -n "$bootstrap_url" ]; then
	registration_loaded=no
	[ "$bootstrap_archive_ready" = yes ] || die "bootstrap archive was not prepared"

	registration=$bootstrap_stage/nix-termux/bootstrap.registration
	NIX_TERMUX_STORE_DIR=$bootstrap_stage/nix \
		NIX_TERMUX_ROOT_DIR=$bootstrap_stage/root \
		NIX_TERMUX_PROFILE_DIR=$bootstrap_stage/nix/var/nix/profiles/default \
		NIX_TERMUX_USER_PROFILE_DIR=$bootstrap_stage/nix/var/nix/profiles/per-user/termux/profile \
		NIX_TERMUX_SSL_CERT_FILE=$bootstrap_stage/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt \
		NIX_TERMUX_NIX_CONF=$bootstrap_stage/root/etc/nix/nix.conf \
		NIX_TERMUX_RESOLV_CONF=$bootstrap_stage/root/etc/resolv.conf \
		sh "$state_dir/bin/nix-termux" exec nix-store --load-db <"$registration"
	registration_loaded=yes

	(cd "$bootstrap_stage" && tar -cf - .) | tar -xf - -C "$state_dir"
	registration=$state_dir/nix-termux/bootstrap.registration

	{
		printf 'bootstrap_url=%s\n' "$bootstrap_url"
		printf 'bootstrap_sha256=%s\n' "$bootstrap_sha256"
		printf 'registration=%s\n' "$registration"
		printf 'registration_loaded=%s\n' "$registration_loaded"
	} | write_file "$state_dir/etc/bootstrap-activation.conf"
fi

for name in $wrapper_names; do
	backup_prefix_command "$name"
done

cat >"$prefix/bin/nix-termux" <<EOF
#!$prefix/bin/sh
# nix-termux managed wrapper
export NIX_TERMUX_LIBEXEC='$state_dir/runtime'
exec sh '$state_dir/bin/nix-termux' "\$@"
EOF
chmod 755 "$prefix/bin/nix-termux"

for name in $wrapper_names; do
	[ "$name" = nix-termux ] && continue
	cat >"$prefix/bin/$name" <<EOF
#!$prefix/bin/sh
# nix-termux managed wrapper
exec '$prefix/bin/nix-termux' exec $name "\$@"
EOF
	chmod 755 "$prefix/bin/$name"
done

{
	printf 'runtime_version=%s\n' "$runtime_version"
	printf 'termux_arch=%s\n' "$termux_arch"
	printf 'channel_url=%s\n' "$channel_url"
	printf 'channel_base_url=%s\n' "$channel_base_url"
	printf 'runtime_archive_url=%s\n' "$runtime_archive_url"
	printf 'runtime_archive_sha256=%s\n' "$runtime_archive_sha256"
	printf 'bootstrap_manifest_url=%s\n' "$bootstrap_manifest_url"
	printf 'bootstrap_url=%s\n' "$bootstrap_url"
	printf 'bootstrap_sha256=%s\n' "$bootstrap_sha256"
} | write_file "$state_dir/etc/nix-termux.conf"

printf '%s\n' "Installed nix-termux to $state_dir"
printf '%s\n' "Run: nix-termux doctor"

#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

usage() {
	cat <<'EOF'
Usage: serve-release.sh [--check] <release-dir> [host] [port]

Serve a nix-termux release directory for local device validation and print the
Termux commands needed to install and smoke-test it.

Arguments:
  release-dir  Directory produced by `nix build .#release`.
  host         Hostname or LAN IP address reachable from the Android device.
  port         HTTP port to serve. Defaults to 8000.

Options:
  --check      Validate release directory contents and checksums, then exit.
EOF
}

die() {
	printf 'serve-release.sh: %s\n' "$*" >&2
	exit 1
}

json_string_value_n() {
	key=$1
	index=$2
	file=$3

	sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | sed -n "${index}p"
}

manifest_arch_from_name() {
	name=$1

	name=${name#nix-termux-channel-}
	name=${name#nix-termux-bootstrap-}
	name=${name%.json}
	printf '%s\n' "$name"
}

is_local_filename() {
	case $1 in
	"" | */* | .*)
		return 1
		;;
	*)
		return 0
		;;
	esac
}

[ "${1:-}" != "-h" ] || {
	usage
	exit 0
}
[ "${1:-}" != "--help" ] || {
	usage
	exit 0
}

check_only=no
if [ "${1:-}" = "--check" ]; then
	check_only=yes
	shift
fi

[ "$#" -ge 1 ] && [ "$#" -le 3 ] || {
	usage >&2
	exit 2
}

if [ "$check_only" = yes ] && [ "$#" -ne 1 ]; then
	usage >&2
	exit 2
fi

release_dir=$1
host=${2:-}
port=${3:-8000}

validate_release_dir() {
	[ -d "$release_dir" ] || die "release directory not found: $release_dir"
	command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required to verify release files"
	command -v sed >/dev/null 2>&1 || die "sed is required to verify release manifests"

	for file in \
		install.sh \
		install.sh.sha256 \
		nix-termux-runtime.tar.gz \
		nix-termux-runtime.tar.gz.sha256 \
		SHA256SUMS; do
		[ -r "$release_dir/$file" ] || die "release directory missing $file"
	done

	set -- "$release_dir"/nix-termux-channel-*.json
	[ -r "$1" ] || die "release directory missing nix-termux-channel-*.json"
	for channel in "$@"; do
		channel_name=$(basename -- "$channel")
		expected_arch=$(manifest_arch_from_name "$channel_name")
		grep -Eq '"schemaVersion"[[:space:]]*:[[:space:]]*1([,[:space:]}]|$)' "$channel" ||
			die "$channel_name has unsupported schemaVersion"
		runtime_url=$(json_string_value_n url 1 "$channel")
		runtime_sha=$(json_string_value_n sha256 1 "$channel")
		bootstrap_manifest_url=$(json_string_value_n url 2 "$channel")
		channel_arch=$(json_string_value_n termuxArch 1 "$channel")
		[ -n "$channel_arch" ] ||
			die "$channel_name missing platform.termuxArch"
		[ "$channel_arch" = "$expected_arch" ] ||
			die "$channel_name platform.termuxArch mismatch: expected $expected_arch got $channel_arch"
		[ "$runtime_url" = "nix-termux-runtime.tar.gz" ] ||
			die "$channel_name references unsupported runtime URL: $runtime_url"
		is_local_filename "$bootstrap_manifest_url" ||
			die "$channel_name references unsafe bootstrap manifest URL: $bootstrap_manifest_url"
		[ -r "$release_dir/$bootstrap_manifest_url" ] ||
			die "$channel_name references missing bootstrap manifest: $bootstrap_manifest_url"
		bootstrap_manifest_arch=$(manifest_arch_from_name "$bootstrap_manifest_url")
		[ "$bootstrap_manifest_arch" = "$expected_arch" ] ||
			die "$channel_name references bootstrap manifest for $bootstrap_manifest_arch"
		actual_runtime_sha=$(sha256sum "$release_dir/nix-termux-runtime.tar.gz")
		actual_runtime_sha=${actual_runtime_sha%% *}
		[ "$runtime_sha" = "$actual_runtime_sha" ] ||
			die "$channel_name runtime sha256 mismatch"
	done

	set -- "$release_dir"/nix-termux-bootstrap-*.json
	[ -r "$1" ] || die "release directory missing nix-termux-bootstrap-*.json"
	for manifest in "$@"; do
		base=${manifest%.json}
		manifest_name=$(basename -- "$manifest")
		expected_arch=$(manifest_arch_from_name "$manifest_name")
		grep -Eq '"schemaVersion"[[:space:]]*:[[:space:]]*1([,[:space:]}]|$)' "$manifest" ||
			die "$manifest_name has unsupported schemaVersion"
		archive_url=$(json_string_value_n url 1 "$manifest")
		archive_sha=$(json_string_value_n sha256 1 "$manifest")
		manifest_arch=$(json_string_value_n termuxArch 1 "$manifest")
		expected_archive=$(basename -- "$base.tar.gz")
		[ -n "$manifest_arch" ] ||
			die "$manifest_name missing platform.termuxArch"
		[ "$manifest_arch" = "$expected_arch" ] ||
			die "$manifest_name platform.termuxArch mismatch: expected $expected_arch got $manifest_arch"
		[ "$archive_url" = "$expected_archive" ] ||
			die "$manifest_name references unsupported archive URL: $archive_url"
		[ -r "$base.tar.gz" ] || die "release directory missing $(basename -- "$base.tar.gz")"
		[ -r "$base.registration" ] || die "release directory missing $(basename -- "$base.registration")"
		actual_archive_sha=$(sha256sum "$base.tar.gz")
		actual_archive_sha=${actual_archive_sha%% *}
		[ "$archive_sha" = "$actual_archive_sha" ] ||
			die "$manifest_name archive sha256 mismatch"
	done

	(cd "$release_dir" && sha256sum -c install.sh.sha256 >/dev/null) ||
		die "installer checksum verification failed"
	(cd "$release_dir" && sha256sum -c SHA256SUMS >/dev/null) ||
		die "release checksum verification failed"
}

validate_release_dir

if [ "$check_only" = yes ]; then
	printf 'release directory ok: %s\n' "$release_dir"
	exit 0
fi

[ -n "$host" ] || {
	usage >&2
	exit 2
}

case $port in
'' | *[!0-9]*)
	die "port must be numeric"
	;;
esac

command -v python3 >/dev/null 2>&1 || die "python3 is required to serve release files"

base_url=http://$host:$port

cat <<EOF
Run this inside stock Termux on the Android device:

pkg install proot curl tar xz coreutils
export NIX_TERMUX_CHANNEL_BASE_URL=$base_url
tmp_dir=\$(mktemp -d)
trap 'rm -rf "\$tmp_dir"' EXIT INT TERM
curl -fL "\$NIX_TERMUX_CHANNEL_BASE_URL/install.sh" -o "\$tmp_dir/install.sh"
curl -fL "\$NIX_TERMUX_CHANNEL_BASE_URL/install.sh.sha256" -o "\$tmp_dir/install.sh.sha256"
(cd "\$tmp_dir" && sha256sum -c install.sh.sha256)
sh "\$tmp_dir/install.sh"
nix-termux doctor --json
nix-termux smoke-test --network

Serving $release_dir at $base_url
Press Ctrl-C to stop the server.
EOF

cd "$release_dir"
exec python3 -m http.server "$port" --bind "$host"

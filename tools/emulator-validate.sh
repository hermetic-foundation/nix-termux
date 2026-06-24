#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

usage() {
	cat <<'EOF'
Usage: emulator-validate.sh [options]

Start or use an Android emulator, serve a local nix-termux release, and stage
the Termux-side validation script through adb.

Options:
  --avd NAME             Android Virtual Device name to start.
  --serial SERIAL        adb serial to target. Defaults to emulator-5554.
  --release-dir DIR      Release directory. Defaults to result.
  --bind-host HOST       Host interface for the HTTP server. Defaults to 127.0.0.1.
  --port PORT            Host HTTP port. Defaults to 8000.
  --device-base-url URL  URL reachable from the emulator.
                          Defaults to http://10.0.2.2:<port>.
  --termux-apk PATH      Install this Termux APK before staging validation.
  --remote-path PATH     Device path for validation script.
                          Defaults to /sdcard/Download/nix-termux-validate.sh.
  --network              Run `nix-termux smoke-test --network`.
  --no-start             Do not start an emulator; use an already running device.
  --no-launch            Do not try to bring Termux to the foreground.
  --dry-run              Print the planned commands without executing them.
EOF
}

die() {
	printf 'emulator-validate.sh: %s\n' "$*" >&2
	exit 1
}

shell_quote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

adb_cmd() {
	adb -s "$serial" "$@"
}

device_online() {
	adb_cmd get-state >/dev/null 2>&1
}

wait_for_boot() {
	timeout_seconds=$1
	elapsed=0

	adb_cmd wait-for-device
	while [ "$elapsed" -lt "$timeout_seconds" ]; do
		boot_completed=$(adb_cmd shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
		if [ "$boot_completed" = 1 ]; then
			return 0
		fi
		sleep 2
		elapsed=$((elapsed + 2))
	done

	die "device $serial did not finish booting within ${timeout_seconds}s"
}

run_or_print() {
	if [ "$dry_run" = yes ]; then
		printf '+'
		for arg in "$@"; do
			printf ' %s' "$(shell_quote "$arg")"
		done
		printf '\n'
	else
		"$@"
	fi
}

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

avd=
serial=emulator-5554
release_dir=result
bind_host=127.0.0.1
port=8000
device_base_url=
termux_apk=
remote_path=/sdcard/Download/nix-termux-validate.sh
network=no
start_emulator=yes
launch=yes
dry_run=no

while [ "$#" -gt 0 ]; do
	case $1 in
	--avd)
		[ "$#" -ge 2 ] || die "--avd requires a value"
		[ -n "$2" ] || die "--avd requires a non-empty value"
		avd=$2
		shift 2
		;;
	--serial)
		[ "$#" -ge 2 ] || die "--serial requires a value"
		[ -n "$2" ] || die "--serial requires a non-empty value"
		case $2 in
		*[[:space:]]*) die "--serial must not contain whitespace" ;;
		esac
		serial=$2
		shift 2
		;;
	--release-dir)
		[ "$#" -ge 2 ] || die "--release-dir requires a value"
		[ -n "$2" ] || die "--release-dir requires a non-empty value"
		release_dir=$2
		shift 2
		;;
	--bind-host)
		[ "$#" -ge 2 ] || die "--bind-host requires a value"
		[ -n "$2" ] || die "--bind-host requires a non-empty value"
		bind_host=$2
		shift 2
		;;
	--port)
		[ "$#" -ge 2 ] || die "--port requires a value"
		port=$2
		shift 2
		;;
	--device-base-url)
		[ "$#" -ge 2 ] || die "--device-base-url requires a value"
		[ -n "$2" ] || die "--device-base-url requires a non-empty value"
		device_base_url=$2
		shift 2
		;;
	--termux-apk)
		[ "$#" -ge 2 ] || die "--termux-apk requires a value"
		[ -n "$2" ] || die "--termux-apk requires a non-empty value"
		termux_apk=$2
		shift 2
		;;
	--remote-path)
		[ "$#" -ge 2 ] || die "--remote-path requires a value"
		[ -n "$2" ] || die "--remote-path requires a non-empty value"
		case $2 in
		/*) ;;
		*) die "--remote-path must be an absolute device path" ;;
		esac
		remote_path=$2
		shift 2
		;;
	--network)
		network=yes
		shift
		;;
	--no-start)
		start_emulator=no
		shift
		;;
	--no-launch)
		launch=no
		shift
		;;
	--dry-run)
		dry_run=yes
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	-*)
		usage >&2
		exit 2
		;;
	*)
		usage >&2
		exit 2
		;;
	esac
done

case $bind_host in
*[[:space:]/]* | -*) die "--bind-host must not contain whitespace, slashes, or a leading dash" ;;
esac

case $port in
'' | *[!0-9]*) die "--port must be numeric" ;;
esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "--port must be between 1 and 65535"

if [ -z "$device_base_url" ]; then
	device_base_url=http://10.0.2.2:$port
fi
case $device_base_url in
http://* | https://*) ;;
*) die "--device-base-url must start with http:// or https://" ;;
esac
case $device_base_url in
*[[:space:]]*) die "--device-base-url must not contain whitespace" ;;
esac

if [ -n "$termux_apk" ] && [ ! -r "$termux_apk" ]; then
	die "Termux APK not readable: $termux_apk"
fi

if [ "$dry_run" = yes ]; then
	run_or_print "$repo_root/tools/serve-release.sh" --check "$release_dir"
	if [ "$start_emulator" = yes ] && [ -n "$avd" ]; then
		run_or_print emulator -avd "$avd" -no-snapshot-save -netdelay none -netspeed full
	fi
	if [ -n "$termux_apk" ]; then
		run_or_print adb -s "$serial" install -r "$termux_apk"
	fi
	run_or_print "$repo_root/tools/serve-release.sh" "$release_dir" "$bind_host" "$port"
	adb_validate_args=
	if [ "$network" = yes ]; then
		adb_validate_args=--network
	fi
	if [ "$launch" = yes ]; then
		run_or_print "$repo_root/tools/adb-validate.sh" --serial "$serial" --remote-path "$remote_path" $adb_validate_args "$device_base_url"
	else
		run_or_print "$repo_root/tools/adb-validate.sh" --serial "$serial" --remote-path "$remote_path" --no-launch $adb_validate_args "$device_base_url"
	fi
	exit 0
fi

require_command adb
require_command python3
"$repo_root/tools/serve-release.sh" --check "$release_dir"

emulator_pid=
server_pid=

cleanup() {
	if [ -n "$server_pid" ]; then
		kill "$server_pid" >/dev/null 2>&1 || true
	fi
	if [ -n "$emulator_pid" ]; then
		kill "$emulator_pid" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT INT TERM

if ! device_online; then
	if [ "$start_emulator" != yes ]; then
		die "device $serial is not online"
	fi
	[ -n "$avd" ] || die "--avd is required when no emulator is already online"
	require_command emulator
	emulator -avd "$avd" -no-snapshot-save -netdelay none -netspeed full >/dev/null 2>&1 &
	emulator_pid=$!
fi

wait_for_boot 180

if [ -n "$termux_apk" ]; then
	adb_cmd install -r "$termux_apk"
fi

"$repo_root/tools/serve-release.sh" "$release_dir" "$bind_host" "$port" &
server_pid=$!
sleep 2

adb_validate_args=
if [ "$network" = yes ]; then
	adb_validate_args=--network
fi

if [ "$launch" = yes ]; then
	"$repo_root/tools/adb-validate.sh" --serial "$serial" --remote-path "$remote_path" $adb_validate_args "$device_base_url"
else
	"$repo_root/tools/adb-validate.sh" --serial "$serial" --remote-path "$remote_path" --no-launch $adb_validate_args "$device_base_url"
fi

cat <<EOF

Release server is still running for the emulator.
Run the printed command inside Termux, then press Ctrl-C here when validation
finishes.
EOF

while :; do
	sleep 3600
done

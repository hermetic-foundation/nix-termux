#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

artifact=${1:?usage: channel-artifact.sh <artifact-dir> [runtime-artifact-dir]}
runtime_artifact=${2:-}

exactly_one() {
	pattern=$1
	label=$2
	count=$(find "$artifact" -name "$pattern" | wc -l)
	[ "$count" -eq 1 ] || {
		printf 'expected exactly one %s, found %s\n' "$label" "$count" >&2
		exit 1
	}
	find "$artifact" -name "$pattern" | head -n 1
}

channel=$(exactly_one 'nix-termux-channel-*.json' 'channel manifest')
bootstrap_manifest=$(exactly_one 'nix-termux-bootstrap-*.json' 'bootstrap manifest beside channel')

channel_name=$(basename "$channel")
channel_arch=${channel_name#nix-termux-channel-}
channel_arch=${channel_arch%.json}
case $channel_arch in
aarch64) expected_system=aarch64-linux ;;
arm) expected_system=armv7l-linux ;;
i686) expected_system=i686-linux ;;
x86_64) expected_system=x86_64-linux ;;
*)
	printf 'unsupported channel architecture: %s\n' "$channel_arch" >&2
	exit 1
	;;
esac

jq -e --arg channel_arch "$channel_arch" --arg expected_system "$expected_system" '
  .schemaVersion == 1
  and .platform.termuxArch == $channel_arch
  and .platform.nixSystem == $expected_system
  and .runtime.url == "nix-termux-runtime.tar.gz"
  and (.runtime.sha256 | test("^[0-9a-f]{64}$"))
  and (.bootstrapManifest.url | length > 0)
' "$channel" >/dev/null

bootstrap_name=$(basename "$bootstrap_manifest")
jq -e --arg bootstrap_name "$bootstrap_name" \
	'.bootstrapManifest.url == $bootstrap_name' "$channel" >/dev/null
bootstrap_arch=${bootstrap_name#nix-termux-bootstrap-}
bootstrap_arch=${bootstrap_arch%.json}
[ "$bootstrap_arch" = "$channel_arch" ] || {
	printf 'channel references bootstrap architecture mismatch: expected %s got %s\n' "$channel_arch" "$bootstrap_arch" >&2
	exit 1
}

if [ -n "$runtime_artifact" ]; then
	runtime_archive=$runtime_artifact/nix-termux-runtime.tar.gz
	[ -f "$runtime_archive" ] || {
		printf '%s\n' "missing runtime archive for channel hash check" >&2
		exit 1
	}
	runtime_sha=$(sha256sum "$runtime_archive" | awk '{print $1}')
	jq -e --arg runtime_sha "$runtime_sha" \
		'.runtime.sha256 == $runtime_sha' "$channel" >/dev/null
fi

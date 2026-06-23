#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0-or-later

set -eu

artifact=${1:?usage: channel-artifact.sh <artifact-dir>}

channel=$(find "$artifact" -name 'nix-termux-channel-*.json' | head -n 1)
bootstrap_manifest=$(find "$artifact" -name 'nix-termux-bootstrap-*.json' | head -n 1)

[ -n "$channel" ] || {
	printf '%s\n' "missing channel manifest" >&2
	exit 1
}
[ -n "$bootstrap_manifest" ] || {
	printf '%s\n' "missing bootstrap manifest beside channel" >&2
	exit 1
}

jq -e '
  .schemaVersion == 1
  and (.runtime.url | length > 0)
  and (.runtime.sha256 | test("^[0-9a-f]{64}$"))
  and (.bootstrapManifest.url | length > 0)
' "$channel" >/dev/null

bootstrap_name=$(basename "$bootstrap_manifest")
jq -e --arg bootstrap_name "$bootstrap_name" \
	'.bootstrapManifest.url == $bootstrap_name' "$channel" >/dev/null

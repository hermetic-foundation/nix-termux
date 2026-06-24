#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later

import json
import sys
from pathlib import Path

import jsonschema


def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate(schema, path):
    jsonschema.Draft202012Validator(schema).validate(load_json(path))


def assert_invalid(schema, manifest, message):
    try:
        jsonschema.Draft202012Validator(schema).validate(manifest)
    except jsonschema.ValidationError:
        return
    raise SystemExit(message)


def exactly_one(directory, pattern):
    matches = sorted(Path(directory).glob(pattern))
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one {pattern} in {directory}, found {len(matches)}"
        )
    return matches[0]


def mismatched_nix_system(termux_arch):
    if termux_arch == "x86_64":
        return "aarch64-linux"
    return "x86_64-linux"


def main():
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: manifest-schemas.py <bootstrap-schema> <channel-schema> "
            "<bootstrap-artifact-dir> <channel-artifact-dir>"
        )

    bootstrap_schema = load_json(Path(sys.argv[1]))
    channel_schema = load_json(Path(sys.argv[2]))
    bootstrap_artifact = Path(sys.argv[3])
    channel_artifact = Path(sys.argv[4])

    jsonschema.Draft202012Validator.check_schema(bootstrap_schema)
    jsonschema.Draft202012Validator.check_schema(channel_schema)

    example_bootstrap = load_json(Path("bootstrap/example-manifest.json"))
    validate(bootstrap_schema, Path("bootstrap/example-manifest.json"))
    validate(bootstrap_schema, exactly_one(bootstrap_artifact, "nix-termux-bootstrap-*.json"))
    validate(bootstrap_schema, exactly_one(channel_artifact, "nix-termux-bootstrap-*.json"))
    channel_manifest_path = exactly_one(channel_artifact, "nix-termux-channel-*.json")
    validate(channel_schema, channel_manifest_path)

    invalid_bootstrap = dict(example_bootstrap)
    invalid_bootstrap["archive"] = dict(example_bootstrap["archive"])
    invalid_bootstrap["archive"]["url"] = "bootstrap bad.tar.gz"
    assert_invalid(
        bootstrap_schema,
        invalid_bootstrap,
        "bootstrap schema accepted archive.url with whitespace",
    )

    invalid_bootstrap = dict(example_bootstrap)
    invalid_bootstrap["platform"] = dict(example_bootstrap["platform"])
    invalid_bootstrap["platform"]["nixSystem"] = mismatched_nix_system(
        invalid_bootstrap["platform"]["termuxArch"]
    )
    assert_invalid(
        bootstrap_schema,
        invalid_bootstrap,
        "bootstrap schema accepted mismatched platform nixSystem",
    )

    channel_manifest = load_json(channel_manifest_path)
    invalid_channel = dict(channel_manifest)
    invalid_channel["runtime"] = dict(channel_manifest["runtime"])
    invalid_channel["runtime"]["url"] = "runtime bad.tar.gz"
    assert_invalid(
        channel_schema,
        invalid_channel,
        "channel schema accepted runtime.url with whitespace",
    )

    invalid_channel = dict(channel_manifest)
    invalid_channel["bootstrapManifest"] = dict(channel_manifest["bootstrapManifest"])
    invalid_channel["bootstrapManifest"]["url"] = "bootstrap manifest.json"
    assert_invalid(
        channel_schema,
        invalid_channel,
        "channel schema accepted bootstrapManifest.url with whitespace",
    )

    invalid_channel = dict(channel_manifest)
    invalid_channel["platform"] = dict(channel_manifest["platform"])
    invalid_channel["platform"]["nixSystem"] = mismatched_nix_system(
        invalid_channel["platform"]["termuxArch"]
    )
    assert_invalid(
        channel_schema,
        invalid_channel,
        "channel schema accepted mismatched platform nixSystem",
    )


if __name__ == "__main__":
    main()

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


def exactly_one(directory, pattern):
    matches = sorted(Path(directory).glob(pattern))
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one {pattern} in {directory}, found {len(matches)}"
        )
    return matches[0]


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

    validate(bootstrap_schema, Path("bootstrap/example-manifest.json"))
    validate(bootstrap_schema, exactly_one(bootstrap_artifact, "nix-termux-bootstrap-*.json"))
    validate(bootstrap_schema, exactly_one(channel_artifact, "nix-termux-bootstrap-*.json"))
    validate(channel_schema, exactly_one(channel_artifact, "nix-termux-channel-*.json"))


if __name__ == "__main__":
    main()

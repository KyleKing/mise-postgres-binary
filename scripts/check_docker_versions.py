#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Verify docker-bake.hcl and docker/Dockerfile.* match scripts/postgres-versions.json.

Unlike sync-postgres-versions.py (which fetches new upstream releases), this only
checks that the already-recorded versions are consistently applied everywhere.
"""

import argparse
import json
import re
import sys
from dataclasses import dataclass

from _script_utils import REPO_ROOT

VERSIONS_FILE = REPO_ROOT / "scripts/postgres-versions.json"
DOCKER_BAKE = REPO_ROOT / "docker/docker-bake.hcl"
DOCKERFILES = sorted((REPO_ROOT / "docker").glob("Dockerfile.*"))


@dataclass(frozen=True)
class Args:
    fix: bool


def _parse_args() -> Args:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fix",
        action="store_true",
        help="Rewrite docker-bake.hcl/Dockerfiles to match postgres-versions.json",
    )
    return Args(fix=parser.parse_args().fix)


def _expected_versions() -> dict[str, str]:
    return json.loads(VERSIONS_FILE.read_text())


def _bake_mismatch(versions: dict[str, str]) -> bool:
    oldest_major = versions["oldest"].split(".")[0]
    newest_major = versions["newest"].split(".")[0]
    expected = {oldest_major: versions["oldest"], newest_major: versions["newest"]}
    found = dict(re.findall(r'pg(\d+)\s*=\s*"([\d.]+)"', DOCKER_BAKE.read_text()))
    return found != expected


def _stale_dockerfiles(versions: dict[str, str]) -> list:
    return [
        dockerfile
        for dockerfile in DOCKERFILES
        if f"ARG POSTGRES_VERSION={versions['oldest']}" not in dockerfile.read_text()
    ]


def main() -> int:
    args = _parse_args()
    versions = _expected_versions()

    bake_mismatch = _bake_mismatch(versions)
    stale_dockerfiles = _stale_dockerfiles(versions)

    if not bake_mismatch and not stale_dockerfiles:
        print("OK: docker-bake.hcl and Dockerfiles match scripts/postgres-versions.json")
        return 0

    if not args.fix:
        if bake_mismatch:
            print("Mismatch: docker-bake.hcl PG_VERSIONS out of sync with postgres-versions.json")
        for dockerfile in stale_dockerfiles:
            print(f"Mismatch: {dockerfile.relative_to(REPO_ROOT)} POSTGRES_VERSION out of sync")
        print("Run with --fix, or: scripts/sync-postgres-versions.py --apply")
        return 1

    if bake_mismatch:
        oldest_major = versions["oldest"].split(".")[0]
        newest_major = versions["newest"].split(".")[0]
        new_block = f"""variable "PG_VERSIONS" {{
  default = {{
    pg{oldest_major} = "{versions["oldest"]}"
    pg{newest_major} = "{versions["newest"]}"
  }}
}}"""
        content = re.sub(
            r'variable "PG_VERSIONS" \{[^}]+\}[^}]*\}',
            new_block,
            DOCKER_BAKE.read_text(),
            flags=re.DOTALL,
        )
        DOCKER_BAKE.write_text(content)

    for dockerfile in stale_dockerfiles:
        content = re.sub(
            r"POSTGRES_VERSION=\d+\.\d+\.\d+",
            f"POSTGRES_VERSION={versions['oldest']}",
            dockerfile.read_text(),
        )
        dockerfile.write_text(content)

    still_bake_mismatch = _bake_mismatch(versions)
    still_stale = _stale_dockerfiles(versions)
    if still_bake_mismatch or still_stale:
        print("Still mismatched after --fix")
        return 1
    print("Fixed: docker-bake.hcl and Dockerfiles now match scripts/postgres-versions.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())

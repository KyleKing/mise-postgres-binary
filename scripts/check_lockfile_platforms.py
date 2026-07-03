#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Verify mise.lock has entries for all supported platforms, for every tool that ships platform-specific binaries."""

import argparse
import subprocess
import sys
import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
MISE_LOCK = REPO_ROOT / "mise.lock"
ALL_PLATFORMS = [
    "linux-arm64",
    "linux-arm64-musl",
    "linux-x64",
    "linux-x64-musl",
    "macos-arm64",
    "macos-x64",
    "windows-x64",
]

# Platforms a tool's upstream releases don't publish, so `mise lock` can never fill these in.
KNOWN_GAPS = {
    "hk": {"macos-x64"},  # jdx/hk only ships linux, darwin/arm64, windows
}


def _tool_entries() -> dict[str, list[dict]]:
    data = tomllib.loads(MISE_LOCK.read_text())
    tools = data.get("tools", {})
    return {
        name: entries if isinstance(entries, list) else [entries]
        for name, entries in tools.items()
    }


def _missing_platforms() -> dict[str, set[str]]:
    missing = {}
    for name, entries in _tool_entries().items():
        for entry in entries:
            present = {
                key.removeprefix("platforms.")
                for key in entry
                if key.startswith("platforms.")
            }
            if not present:
                continue
            gap = set(ALL_PLATFORMS) - present - KNOWN_GAPS.get(name, set())
            if gap:
                missing[f"{name}@{entry.get('version')}"] = gap
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fix",
        action="store_true",
        help="Run `mise lock` for all platforms to fill gaps",
    )
    args = parser.parse_args()

    missing = _missing_platforms()
    if not missing:
        print("OK: mise.lock has all platforms for every locked tool")
        return 0

    if not args.fix:
        for tool, gap in missing.items():
            print(f"Missing platforms for {tool}: {', '.join(sorted(gap))}")
        print("Run with --fix, or: mise lock --platform " + ",".join(ALL_PLATFORMS))
        return 1

    subprocess.run(
        ["mise", "lock", "--platform", ",".join(ALL_PLATFORMS)],
        cwd=REPO_ROOT,
        check=True,
    )
    still_missing = _missing_platforms()
    if still_missing:
        for tool, gap in still_missing.items():
            print(f"Still missing platforms for {tool}: {', '.join(sorted(gap))}")
        return 1
    print("Fixed: mise.lock now has all platforms for every locked tool")
    return 0


if __name__ == "__main__":
    sys.exit(main())

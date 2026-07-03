#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Verify or update the hk PKL package URLs in hk.pkl to match mise.lock."""

import argparse
import re
import sys
import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
HK_PKL = REPO_ROOT / "hk.pkl"


def _lock_version() -> str:
    data = tomllib.loads((REPO_ROOT / "mise.lock").read_text())
    entries = data.get("tools", {}).get("hk", [])
    if not entries:
        raise SystemExit("hk not found in mise.lock — run: mise lock")
    return entries[0]["version"]


def _pkl_version() -> str:
    if m := re.search(r"hk@([^#]+)#", HK_PKL.read_text()):
        return m.group(1)
    raise SystemExit("hk version not found in hk.pkl package URL")


def _update_pkl(new_version: str) -> None:
    content = HK_PKL.read_text()
    updated = re.sub(
        r"/releases/download/v[^/]+/hk@[^#]+#",
        f"/releases/download/v{new_version}/hk@{new_version}#",
        content,
    )
    HK_PKL.write_text(updated)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fix", action="store_true", help="Update hk.pkl to match mise.lock")
    args = parser.parse_args()

    lock = _lock_version()
    pkl = _pkl_version()

    if lock == pkl:
        print(f"OK: hk version consistent ({lock})")
        return 0

    if not args.fix:
        print(f"Version mismatch: mise.lock pins hk {lock} but hk.pkl references {pkl}")
        print(f"Run with --fix to update hk.pkl to v{lock}")
        return 1

    _update_pkl(lock)
    print(f"Updated hk.pkl: {pkl} -> {lock}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

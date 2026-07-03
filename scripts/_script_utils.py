"""Shared helper for scripts that inspect mise.lock."""

import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
MISE_LOCK = REPO_ROOT / "mise.lock"


def load_tools() -> dict[str, list[dict]]:
    return tomllib.loads(MISE_LOCK.read_text()).get("tools", {})

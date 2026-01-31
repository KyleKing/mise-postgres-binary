#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx"]
# ///
"""Update PostgreSQL versions across all project files.

Source of truth: .versions.json (newest/oldest of 5 supported major versions)
Updates: ci.yml, docker/docker-bake.hcl, mise.toml, docker/Dockerfile.*
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

import httpx

REPO_ROOT = Path(__file__).parent.parent
VERSIONS_FILE = REPO_ROOT / ".versions.json"
CI_WORKFLOW = REPO_ROOT / ".github/workflows/ci.yml"
DOCKER_BAKE = REPO_ROOT / "docker/docker-bake.hcl"
MISE_TOML = REPO_ROOT / "mise.toml"
DOCKERFILES = list((REPO_ROOT / "docker").glob("Dockerfile.*"))
NUM_SUPPORTED_VERSIONS = 5
MIN_MAJOR_VERSION = 13


def fetch_available_versions() -> dict[int, str]:
    """Fetch latest patch version for each major from theseus-rs/postgresql-binaries."""
    url = "https://api.github.com/repos/theseus-rs/postgresql-binaries/releases?per_page=100"
    headers = {}
    if github_token := os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {github_token}"
    resp = httpx.get(url, headers=headers if headers else None, timeout=30)
    resp.raise_for_status()

    releases = resp.json()
    latest_by_major: dict[int, str] = {}

    for release in releases:
        version = release.get("tag_name", "")
        if not version:
            continue

        parts = version.split(".")
        if len(parts) < 2:
            continue

        try:
            major = int(parts[0])
        except ValueError:
            continue

        if major < MIN_MAJOR_VERSION:
            continue

        if major not in latest_by_major or _version_tuple(version) > _version_tuple(
            latest_by_major[major]
        ):
            latest_by_major[major] = version

    return latest_by_major


def _version_tuple(version: str) -> tuple[int, ...]:
    """Convert version string to tuple for comparison."""
    return tuple(int(p) for p in version.split(".") if p.isdigit())


def get_recommended_versions(available: dict[int, str]) -> dict[str, str]:
    """Get newest and oldest of the 5 actively supported major versions."""
    supported_majors = sorted(available.keys(), reverse=True)[:NUM_SUPPORTED_VERSIONS]

    if len(supported_majors) < 2:
        oldest = supported_majors[-1] if supported_majors else None
        newest = supported_majors[0] if supported_majors else None
    else:
        oldest = supported_majors[-1]
        newest = supported_majors[0]

    return {
        "newest": available[newest] if newest else "",
        "oldest": available[oldest] if oldest else "",
    }


def read_versions_file() -> dict[str, str]:
    """Read current versions from .versions.json."""
    if not VERSIONS_FILE.exists():
        return {"newest": "", "oldest": ""}
    return json.loads(VERSIONS_FILE.read_text())


def write_versions_file(versions: dict[str, str]) -> None:
    """Write versions to .versions.json."""
    content = json.dumps(versions, indent=2) + "\n"
    VERSIONS_FILE.write_text(content)


def update_ci_workflow(versions: dict[str, str]) -> bool:
    """Update pg_version matrix in CI workflow."""
    content = CI_WORKFLOW.read_text()
    original = content

    versions_str = f'"{versions["newest"]}", "{versions["oldest"]}"'
    content = re.sub(
        r"(pg_version:\s*\[)[^\]]+(\])",
        rf"\g<1>{versions_str}\g<2>",
        content,
    )

    content = re.sub(
        r"postgres-binary:postgres@\d+\.\d+\.\d+",
        f"postgres-binary:postgres@{versions['oldest']}",
        content,
    )

    if content == original:
        return False

    CI_WORKFLOW.write_text(content)
    return True


def update_docker_bake(versions: dict[str, str]) -> bool:
    """Update PG_VERSIONS in docker-bake.hcl."""
    content = DOCKER_BAKE.read_text()
    original = content

    newest_major = versions["newest"].split(".")[0]
    oldest_major = versions["oldest"].split(".")[0]

    new_versions = f'''variable "PG_VERSIONS" {{
  default = {{
    pg{oldest_major} = "{versions["oldest"]}"
    pg{newest_major} = "{versions["newest"]}"
  }}
}}'''

    content = re.sub(
        r'variable "PG_VERSIONS" \{[^}]+\}[^}]*\}',
        new_versions,
        content,
        flags=re.DOTALL,
    )

    if content == original:
        return False

    DOCKER_BAKE.write_text(content)
    return True


def update_mise_toml(versions: dict[str, str]) -> bool:
    """Update test-version-matrix defaults in mise.toml."""
    content = MISE_TOML.read_text()
    original = content

    content = re.sub(
        r'VERSIONS=\("[\d\.]+" "[\d\.]+"\s*(?:"[\d\.]+")?\)',
        f'VERSIONS=("{versions["oldest"]}" "{versions["newest"]}")',
        content,
    )

    if content == original:
        return False

    MISE_TOML.write_text(content)
    return True


def update_dockerfiles(versions: dict[str, str]) -> bool:
    """Update default POSTGRES_VERSION in Dockerfiles."""
    changed = False

    for dockerfile in DOCKERFILES:
        content = dockerfile.read_text()
        new_content = re.sub(
            r"POSTGRES_VERSION=\d+\.\d+\.\d+",
            f"POSTGRES_VERSION={versions['oldest']}",
            content,
        )
        if new_content != content:
            dockerfile.write_text(new_content)
            changed = True

    return changed


def set_github_output(key: str, value: str) -> None:
    """Set GitHub Actions output variable."""
    if output_file := os.environ.get("GITHUB_OUTPUT"):
        with open(output_file, "a") as f:
            f.write(f"{key}={value}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check for updates without modifying files",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply updates to files",
    )
    args = parser.parse_args()

    print("Fetching versions from theseus-rs/postgresql-binaries...")
    available = fetch_available_versions()

    if not available:
        print("ERROR: No versions found", file=sys.stderr)
        return 1

    recommended = get_recommended_versions(available)
    current = read_versions_file()

    print()
    print("=== Current .versions.json ===")
    print(f"  newest: {current.get('newest', 'N/A')}")
    print(f"  oldest: {current.get('oldest', 'N/A')}")

    print()
    supported_majors = sorted(available.keys(), reverse=True)[:NUM_SUPPORTED_VERSIONS]
    print(f"=== Available supported versions ({NUM_SUPPORTED_VERSIONS} most recent majors) ===")
    for major in supported_majors:
        print(f"  PG {major}: {available[major]}")

    print()
    print("=== Recommended versions (newest/oldest of supported) ===")
    print(f"  newest: {recommended['newest']} (PG {recommended['newest'].split('.')[0]})")
    print(f"  oldest: {recommended['oldest']} (PG {recommended['oldest'].split('.')[0]})")

    versions_match = recommended == current

    print()
    if versions_match:
        print("Status: All versions are up to date")
        set_github_output("updated", "false")
        return 0

    print("Status: Update available")

    if args.check:
        set_github_output("updated", "true")
        set_github_output("newest_version", recommended["newest"])
        set_github_output("oldest_version", recommended["oldest"])
        return 0

    if args.apply:
        print()
        print("Applying updates...")

        write_versions_file(recommended)
        print("  .versions.json: updated")

        updated_ci = update_ci_workflow(recommended)
        print(f"  .github/workflows/ci.yml: {'updated' if updated_ci else 'no changes'}")

        updated_bake = update_docker_bake(recommended)
        print(f"  docker-bake.hcl: {'updated' if updated_bake else 'no changes'}")

        updated_mise = update_mise_toml(recommended)
        print(f"  mise.toml: {'updated' if updated_mise else 'no changes'}")

        updated_dockerfiles = update_dockerfiles(recommended)
        print(f"  test/Dockerfile.*: {'updated' if updated_dockerfiles else 'no changes'}")

        set_github_output("updated", "true")
        set_github_output("newest_version", recommended["newest"])
        set_github_output("oldest_version", recommended["oldest"])

        print()
        print("Updates applied. Review changes with: git diff")
        return 0

    print()
    print("Run with --apply to update files")
    print("Run with --check for CI dry-run")
    return 0


if __name__ == "__main__":
    sys.exit(main())

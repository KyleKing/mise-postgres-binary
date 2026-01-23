#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx"]
# ///
"""Update PostgreSQL versions in CI matrix based on theseus-rs/postgresql-binaries releases."""

import argparse
import os
import re
import sys
from pathlib import Path

import httpx

REPO_ROOT = Path(__file__).parent.parent
CI_WORKFLOW = REPO_ROOT / ".github/workflows/ci.yml"
MISE_TOML = REPO_ROOT / "mise.toml"
DOCKERFILES = list((REPO_ROOT / "test").glob("Dockerfile.*"))
NUM_SUPPORTED_VERSIONS = 5  # PostgreSQL actively supports 5 major versions
NUM_TEST_VERSIONS = 3  # Test oldest, middle, and newest of supported versions
MIN_MAJOR_VERSION = 13


def fetch_available_versions() -> dict[int, str]:
    """Fetch latest patch version for each major from theseus-rs/postgresql-binaries."""
    url = "https://api.github.com/repos/theseus-rs/postgresql-binaries/releases?per_page=100"
    resp = httpx.get(url, timeout=30)
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


def get_recommended_versions(available: dict[int, str]) -> list[str]:
    """Get oldest, middle, and newest of the 5 actively supported major versions."""
    # Get the 5 most recent major versions (actively supported)
    supported_majors = sorted(available.keys(), reverse=True)[:NUM_SUPPORTED_VERSIONS]

    if len(supported_majors) < NUM_TEST_VERSIONS:
        # Fall back to all available if less than expected
        return [available[major] for major in supported_majors]

    # Select oldest, middle, and newest
    oldest = supported_majors[-1]  # Last item (smallest major number)
    newest = supported_majors[0]   # First item (largest major number)
    middle = supported_majors[len(supported_majors) // 2]  # Middle item

    # Return in descending order (newest to oldest)
    selected_majors = sorted([newest, middle, oldest], reverse=True)
    return [available[major] for major in selected_majors]


def get_current_versions() -> list[str]:
    """Parse current pg_version array from CI workflow."""
    content = CI_WORKFLOW.read_text()
    match = re.search(r"pg_version:\s*\[([^\]]+)\]", content)
    if not match:
        return []

    versions_str = match.group(1)
    return re.findall(r'"([^"]+)"', versions_str)


def update_ci_workflow(versions: list[str]) -> bool:
    """Update pg_version matrix in CI workflow."""
    content = CI_WORKFLOW.read_text()
    versions_str = ", ".join(f'"{v}"' for v in versions)
    new_content = re.sub(
        r"(pg_version:\s*\[)[^\]]+(\])",
        rf"\g<1>{versions_str}\g<2>",
        content,
    )

    oldest_version = versions[-1]
    new_content = re.sub(
        r"postgres-binary:postgres@\d+\.\d+\.\d+",
        f"postgres-binary:postgres@{oldest_version}",
        new_content,
    )

    if new_content == content:
        return False

    CI_WORKFLOW.write_text(new_content)
    return True


def update_mise_toml(versions: list[str]) -> bool:
    """Update CI_VERSIONS in mise.toml check-versions task."""
    content = MISE_TOML.read_text()
    original = content

    for dockerfile in DOCKERFILES:
        df_content = dockerfile.read_text()
        new_df = re.sub(
            r"POSTGRES_VERSION=\d+\.\d+\.\d+",
            f"POSTGRES_VERSION={versions[-1]}",
            df_content,
        )
        if new_df != df_content:
            dockerfile.write_text(new_df)

    return content != original


def update_dockerfiles(versions: list[str]) -> bool:
    """Update default POSTGRES_VERSION in Dockerfiles."""
    changed = False
    oldest_version = versions[-1]

    for dockerfile in DOCKERFILES:
        content = dockerfile.read_text()
        new_content = re.sub(
            r"POSTGRES_VERSION=\d+\.\d+\.\d+",
            f"POSTGRES_VERSION={oldest_version}",
            content,
        )
        if new_content != content:
            dockerfile.write_text(new_content)
            changed = True

    return changed


def set_github_output(key: str, value: str) -> None:
    """Set GitHub Actions output variable."""
    output_file = os.environ.get("GITHUB_OUTPUT")
    if output_file:
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
    current = get_current_versions()

    print()
    print("=== Current CI matrix ===")
    print(f"  {current}")
    print()
    supported_majors = sorted(available.keys(), reverse=True)[:NUM_SUPPORTED_VERSIONS]
    print(f"=== Available supported versions ({NUM_SUPPORTED_VERSIONS} most recent majors) ===")
    for major in supported_majors:
        print(f"  PG {major}: {available[major]}")

    print()
    print(f"=== Recommended CI matrix (oldest, middle, newest of {NUM_SUPPORTED_VERSIONS} supported) ===")
    for version in recommended:
        major = int(version.split('.')[0])
        role = "newest" if version == recommended[0] else ("oldest" if version == recommended[-1] else "middle")
        print(f"  PG {major}: {version} ({role})")

    versions_match = set(recommended) == set(current)

    print()
    if versions_match:
        print("Status: CI matrix is up to date")
        set_github_output("updated", "false")
        return 0

    print("Status: Update available")
    print()
    versions_str = ", ".join(f'"{v}"' for v in recommended)
    print(f"Recommended: pg_version: [{versions_str}]")

    if args.check:
        set_github_output("updated", "true")
        set_github_output("new_versions", versions_str)
        return 0

    if args.apply:
        print()
        print("Applying updates...")

        updated_ci = update_ci_workflow(recommended)
        print(
            f"  .github/workflows/ci.yml: {'updated' if updated_ci else 'no changes'}"
        )

        updated_dockerfiles = update_dockerfiles(recommended)
        print(
            f"  test/Dockerfile.*: {'updated' if updated_dockerfiles else 'no changes'}"
        )

        set_github_output("updated", "true")
        set_github_output("new_versions", versions_str)

        print()
        print("Updates applied. Review changes with: git diff")
        return 0

    print()
    print("Run with --apply to update files")
    print("Run with --check for CI dry-run")
    return 0


if __name__ == "__main__":
    sys.exit(main())

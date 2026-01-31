#!/usr/bin/env bash
# Run Docker-based tests for mise-postgres-binary using Docker Buildx Bake
#
# Usage:
#   ./docker/run-docker-tests.sh           # Run all default tests
#   ./docker/run-docker-tests.sh debian    # Run all Debian targets
#   ./docker/run-docker-tests.sh alpine    # Run all Alpine targets
#   ./docker/run-docker-tests.sh arm64     # Run ARM64 tests (requires QEMU or ARM host)
#   ./docker/run-docker-tests.sh ci        # Run minimal CI targets

set -euo pipefail

cd "$(dirname "$0")/.."

FILTER="${1:-default}"

echo "=== mise-postgres-binary Docker Tests ==="
echo "Target: $FILTER"
echo ""

build_and_test() {
    local target="$1"
    local image_name="mise-postgres-${target}"

    echo "--- Building: $target ---"
    if ! docker buildx bake "$target"; then
        echo "FAIL: Build failed for $target"
        return 1
    fi

    echo "--- Testing: $target ---"
    if docker run --rm "$image_name"; then
        echo "PASS: $target"
        return 0
    else
        echo "FAIL: Test failed for $target"
        return 1
    fi
}

build_and_test_group() {
    local group="$1"
    shift
    local targets=("$@")

    echo "=== Building group: $group ==="
    if ! docker buildx bake "$group"; then
        echo "FAIL: Build failed for group $group"
        return 1
    fi

    local failed=0
    for target in "${targets[@]}"; do
        local image_name="mise-postgres-${target}"
        echo "--- Testing: $target ---"
        if docker run --rm "$image_name"; then
            echo "PASS: $target"
        else
            echo "FAIL: $target"
            failed=1
        fi
    done

    return $failed
}

FAILED=0

case "$FILTER" in
    debian)
        build_and_test_group debian debian-pg14 debian-pg16 debian-pg18 || FAILED=1
        ;;
    alpine)
        build_and_test_group alpine alpine-pg14 alpine-pg18 || FAILED=1
        ;;
    arm64)
        build_and_test_group arm64 debian-arm64-pg14 alpine-arm64-pg14 || FAILED=1
        ;;
    ci)
        build_and_test_group ci debian-pg14 alpine-pg14 || FAILED=1
        ;;
    default)
        build_and_test_group default \
            debian-pg14 debian-pg16 debian-pg18 \
            alpine-pg14 alpine-pg18 || FAILED=1
        ;;
    all)
        build_and_test_group all \
            debian-pg14 debian-pg16 debian-pg18 \
            alpine-pg14 alpine-pg18 \
            debian-arm64-pg14 alpine-arm64-pg14 || FAILED=1
        ;;
    *)
        # Assume it's a specific target
        build_and_test "$FILTER" || FAILED=1
        ;;
esac

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "=== All tests passed ==="
    exit 0
else
    echo "=== Some tests failed ==="
    exit 1
fi

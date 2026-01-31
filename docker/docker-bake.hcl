# Docker Buildx Bake configuration for testing mise-postgres-binary
#
# Usage:
#   docker buildx bake                    # Build all default targets
#   docker buildx bake --print            # Show resolved configuration
#   docker buildx bake debian             # Build all debian targets
#   docker buildx bake alpine-pg14        # Build specific target
#   docker buildx bake --set *.platform=linux/arm64  # Override platform
#
# To build and run tests:
#   docker buildx bake debian-pg14 && docker run --rm mise-postgres-debian-pg14

variable "PG_VERSIONS" {
  default = {
    pg14 = "14.20.0"
    pg18 = "18.1.0"
  }
}

variable "PLATFORMS" {
  default = {
    amd64 = "linux/amd64"
    arm64 = "linux/arm64"
  }
}

function "make_tag" {
  params = [distro, version_key, arch]
  result = arch == "amd64" ? "mise-postgres-${distro}-${version_key}" : "mise-postgres-${distro}-${arch}-${version_key}"
}

function "cache_config" {
  params = []
  result = {
    cache-from = ["type=gha"]
    cache-to   = ["type=gha,mode=max"]
  }
}

target "_base" {
  context    = "."
  pull       = true
  cache-from = cache_config().cache-from
  cache-to   = cache_config().cache-to
  secret     = ["id=github_token,env=GITHUB_TOKEN"]
}

target "_debian" {
  inherits   = ["_base"]
  dockerfile = "docker/Dockerfile.debian"
  platforms  = [PLATFORMS.amd64]
}

target "_alpine" {
  inherits   = ["_base"]
  dockerfile = "docker/Dockerfile.alpine"
  platforms  = [PLATFORMS.amd64]
}

group "debian" {
  targets = ["debian-pg14", "debian-pg18"]
}

target "debian-pg14" {
  inherits = ["_debian"]
  args     = { POSTGRES_VERSION = PG_VERSIONS.pg14 }
  tags     = [make_tag("debian", "pg14", "amd64")]
}

target "debian-pg18" {
  inherits = ["_debian"]
  args     = { POSTGRES_VERSION = PG_VERSIONS.pg18 }
  tags     = [make_tag("debian", "pg18", "amd64")]
}

group "alpine" {
  targets = ["alpine-pg14", "alpine-pg18"]
}

target "alpine-pg14" {
  inherits = ["_alpine"]
  args     = { POSTGRES_VERSION = PG_VERSIONS.pg14 }
  tags     = [make_tag("alpine", "pg14", "amd64")]
}

target "alpine-pg18" {
  inherits = ["_alpine"]
  args     = { POSTGRES_VERSION = PG_VERSIONS.pg18 }
  tags     = [make_tag("alpine", "pg18", "amd64")]
}

group "arm64" {
  targets = ["debian-arm64-pg14", "alpine-arm64-pg14"]
}

target "debian-arm64-pg14" {
  inherits  = ["_debian"]
  args      = { POSTGRES_VERSION = PG_VERSIONS.pg14 }
  platforms = [PLATFORMS.arm64]
  tags      = [make_tag("debian", "pg14", "arm64")]
}

target "alpine-arm64-pg14" {
  inherits  = ["_alpine"]
  args      = { POSTGRES_VERSION = PG_VERSIONS.pg14 }
  platforms = [PLATFORMS.arm64]
  tags      = [make_tag("alpine", "pg14", "arm64")]
}

group "default" {
  targets = ["debian", "alpine"]
}

group "all" {
  targets = ["debian", "alpine", "arm64"]
}

group "ci" {
  targets = ["debian-pg14", "alpine-pg14"]
}

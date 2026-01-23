# Testing Guide

This document describes how to test mise-postgres-binary locally and in Docker.

## Prerequisites

- [mise](https://mise.jdx.dev/) installed
- Docker (for container tests)

## Local Testing

### Quick Test

```bash
cd mise-postgres-binary

# Install development tools
mise install

# Link the plugin locally
mise plugin link --force postgres-binary "$PWD"

# Verify available versions
mise ls-remote postgres-binary:postgres | head -10

# Install PostgreSQL
mise install postgres-binary:postgres@14.20.0

# Verify installation
mise exec postgres-binary:postgres@14.20.0 -- postgres --version
mise exec postgres-binary:postgres@14.20.0 -- psql --version
```

### Full Local Test

This test verifies the complete workflow including database operations:

```bash
cd mise-postgres-binary

# Link plugin
mise plugin link --force postgres-binary "$PWD"

# Install PostgreSQL
mise install postgres-binary:postgres@16.11.0

# Activate the environment
eval "$(mise activate bash)"  # or zsh/fish
mise use postgres-binary:postgres@16.11.0

# Verify environment variables
echo "PGDATA: $PGDATA"
echo "PGHOME: $PGHOME"

# Check database initialization
ls -la "$PGDATA"
cat "$PGDATA/PG_VERSION"

# Start PostgreSQL
pg_ctl start -D "$PGDATA" -l /tmp/postgres.log -w

# Run queries
psql -c "SELECT version();" postgres
psql -c "CREATE TABLE test (id SERIAL PRIMARY KEY, data TEXT);" postgres
psql -c "INSERT INTO test (data) VALUES ('hello');" postgres
psql -c "SELECT * FROM test;" postgres

# Stop PostgreSQL
pg_ctl stop -D "$PGDATA" -m fast
```

### Testing Multiple Versions

```bash
# Install multiple versions
mise install postgres-binary:postgres@14.20.0
mise install postgres-binary:postgres@16.11.0
mise install postgres-binary:postgres@18.1.0

# Switch between versions
mise use postgres-binary:postgres@14.20.0
postgres --version  # PostgreSQL 15.x

mise use postgres-binary:postgres@16.11.0
postgres --version  # PostgreSQL 16.x
```

### Testing with mise.toml

Create a `mise.toml` in a test project:

```toml
[tools]
"postgres-binary:postgres" = "16.11.0"
```

Then:

```bash
cd test-project
mise install
eval "$(mise activate bash)"
postgres --version
```

## Docker Testing

Docker tests verify the plugin works on different Linux distributions using Docker Buildx Bake.

### Quick Start

```bash
# Build and test all default targets (Debian + Alpine)
docker buildx bake

# Build specific target
docker buildx bake debian-pg14
docker run --rm mise-postgres-debian-pg14

# Build and test a specific distro group
docker buildx bake alpine
```

### Available Targets

```bash
# View all targets and configuration
docker buildx bake --print

# Common target groups
docker buildx bake ci          # Minimal CI targets (debian-pg14, alpine-pg14)
docker buildx bake debian      # All Debian targets (pg14, pg16, pg18)
docker buildx bake alpine      # All Alpine targets (pg14, pg18)
docker buildx bake arm64       # ARM64 targets
docker buildx bake all         # Everything including ARM64
```

### Individual Targets

```bash
# Debian (glibc)
docker buildx bake debian-pg14
docker buildx bake debian-pg16
docker buildx bake debian-pg18

# Alpine (musl)
docker buildx bake alpine-pg14
docker buildx bake alpine-pg18

# ARM64
docker buildx bake debian-arm64-pg14
docker buildx bake alpine-arm64-pg14
```

### Build and Test Workflow

```bash
# Build target
docker buildx bake debian-pg14

# Run tests
docker run --rm mise-postgres-debian-pg14

# Or combine both
docker buildx bake debian-pg14 && docker run --rm mise-postgres-debian-pg14
```

### Advanced Usage

```bash
# Override platform for all targets
docker buildx bake --set *.platform=linux/arm64

# Build with no cache
docker buildx bake --no-cache debian-pg14

# Push to registry (if configured)
docker buildx bake --push debian

# Load into local Docker daemon
docker buildx bake --load alpine-pg14
```

### Test ARM64 (Requires ARM Host or QEMU)

```bash
# Enable ARM64 emulation (if on x86)
docker run --privileged --rm tonistiigi/binfmt --install arm64

# Build and test ARM64 targets
docker buildx bake arm64
docker run --rm mise-postgres-debian-arm64-pg14
```


## CI Testing

The GitHub Actions workflow tests:

| Platform | OS Versions | PostgreSQL Versions |
|----------|-------------|---------------------|
| Ubuntu | 22.04, latest | 14.x, 16.x, 18.x |
| macOS | 13, latest | 14.x, 16.x, 18.x |
| Docker (Debian) | bookworm | 14.x |
| Docker (Alpine) | 3.20 | 14.x |
| Windows | latest | 14.x (experimental) |

### Run CI Locally

```bash
# Lint only
mise run lint

# Full test (link plugin + list versions)
mise run test

# Full CI pipeline
mise run ci
```

## Troubleshooting

### Plugin Not Found

```bash
# Remove and re-link
mise plugin uninstall postgres-binary
mise plugin link --force postgres-binary "$PWD"
```

### Version Not Installing

```bash
# Check available versions
mise ls-remote postgres-binary:postgres

# Enable debug output
MISE_DEBUG=1 mise install postgres-binary:postgres@14.20.0
```

### Docker Build Fails

```bash
# Clean up and rebuild
docker buildx prune -f
docker buildx bake --no-cache debian-pg14
```

### PostgreSQL Won't Start

```bash
# Check logs
cat /tmp/postgres.log

# Check if port 5432 is in use
lsof -i :5432

# Use a different port
pg_ctl start -D "$PGDATA" -o "-p 5433" -l /tmp/postgres.log
```

## Verification Checklist

Before submitting changes, verify:

- [ ] `mise run lint` passes
- [ ] Local installation works: `mise install postgres-binary:postgres@14.20.0`
- [ ] Binary verification: `postgres --version`, `psql --version`
- [ ] Environment setup: `$PGDATA` exists and is initialized
- [ ] Database operations: can start, query, and stop PostgreSQL
- [ ] Docker tests pass: `./test/run-docker-tests.sh`

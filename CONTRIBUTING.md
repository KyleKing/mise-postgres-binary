# Contributing to mise-postgres-binary

## Development Setup

```bash
# Clone the repository
git clone https://github.com/kyleking/mise-postgres-binary
cd mise-postgres-binary

# Install development tools
mise install

# Link plugin for local testing
mise plugin link --force postgres-binary "$PWD"
```

## Project Structure

```
mise-postgres-binary/
├── hooks/
│   ├── backend_list_versions.lua  # Fetch versions from GitHub API
│   ├── backend_install.lua        # Download, verify, extract, initdb
│   └── backend_exec_env.lua       # Set environment variables
├── scripts/
│   └── update-postgres-versions.py  # Version update automation
├── test/
│   ├── Dockerfile.debian          # Debian (glibc) test container
│   ├── Dockerfile.alpine          # Alpine (musl) test container
│   └── run-docker-tests.sh        # Docker test runner
├── .github/workflows/ci.yml       # CI/CD pipeline
├── .versions.json                 # Source of truth for PostgreSQL versions
├── docker-bake.hcl                # Docker Buildx Bake configuration
├── hk.pkl                         # Pre-commit hooks
├── mise.toml                      # Development tools and tasks
├── metadata.lua                   # Plugin metadata
└── stylua.toml                    # Lua formatter configuration
```

## Available Tasks

```bash
mise run format              # Format Lua code with stylua
mise run lint                # Run all linters (luacheck, stylua, actionlint)
mise run test                # Quick test (link plugin, list versions)
mise run test-install        # Full test with database operations
mise run test-docker         # Run Docker-based tests
mise run test-version-matrix # Test oldest and newest PostgreSQL versions
mise run ci                  # Full CI pipeline (lint + test)
mise run clean               # Clean up test installations
mise run check-versions      # Check for new PostgreSQL versions
mise run update-versions     # Apply PostgreSQL version updates
```

## Testing

### Local Testing

Quick test:

```bash
mise plugin link --force postgres-binary "$PWD"
mise ls-remote postgres-binary:postgres | head -10
mise install postgres-binary:postgres@14.20.0
mise exec postgres-binary:postgres@14.20.0 -- postgres --version
```

Full test with database operations:

```bash
mise plugin link --force postgres-binary "$PWD"
mise install postgres-binary:postgres@18.1.0

eval "$(mise activate bash)"
mise use postgres-binary:postgres@18.1.0

echo "PGDATA: $PGDATA"
ls -la "$PGDATA"

pg_ctl start -D "$PGDATA" -l /tmp/postgres.log -w
psql -c "SELECT version();" postgres
pg_ctl stop -D "$PGDATA" -m fast
```

### Docker Testing

Docker tests verify the plugin works on different Linux distributions.

```bash
# Build and test all targets
docker buildx bake

# Build specific target
docker buildx bake debian-pg14
docker run --rm mise-postgres-debian-pg14

# View all available targets
docker buildx bake --print
```

Available target groups:

| Group | Targets |
|-------|---------|
| `ci` | debian-pg14, alpine-pg14 |
| `debian` | debian-pg14, debian-pg18 |
| `alpine` | alpine-pg14, alpine-pg18 |
| `arm64` | debian-arm64-pg14, alpine-arm64-pg14 |
| `all` | All targets |

### CI Pipeline

The GitHub Actions workflow tests:

| Platform | PostgreSQL Versions |
|----------|---------------------|
| Ubuntu (latest) | 14.x, 18.x |
| macOS (latest) | 14.x, 18.x |
| Docker (Debian/Alpine) | 14.x |
| Windows (experimental) | 14.x |

Run CI checks locally:

```bash
mise run lint    # Run linters
mise run test    # Quick test
mise run ci      # Full CI pipeline
```

## Version Management

PostgreSQL versions are managed via `.versions.json`:

```json
{
  "newest": "18.1.0",
  "oldest": "14.20.0"
}
```

The update script propagates versions to all dependent files:

```bash
# Check for updates
./scripts/update-postgres-versions.py --check

# Apply updates
./scripts/update-postgres-versions.py --apply
```

Updated files:
- `.github/workflows/ci.yml`
- `docker-bake.hcl`
- `mise.toml`
- `test/Dockerfile.*`

## Verification Checklist

Before submitting changes:

- [ ] `mise run lint` passes
- [ ] Local installation works: `mise install postgres-binary:postgres@14.20.0`
- [ ] Binary verification: `postgres --version`, `psql --version`
- [ ] Environment setup: `$PGDATA` exists and is initialized
- [ ] Database operations: can start, query, and stop PostgreSQL
- [ ] Docker tests pass: `docker buildx bake ci`

## Troubleshooting

### Plugin Not Found

```bash
mise plugin uninstall postgres-binary
mise plugin link --force postgres-binary "$PWD"
```

### Version Not Installing

```bash
mise ls-remote postgres-binary:postgres
MISE_DEBUG=1 mise install postgres-binary:postgres@14.20.0
```

### Docker Build Fails

```bash
docker buildx prune -f
docker buildx bake --no-cache debian-pg14
```

## How to Contribute

1. Fork the repository
2. Create a feature branch
3. Run `mise run lint` before committing
4. Run `mise run test-install` to verify changes
5. Submit a pull request

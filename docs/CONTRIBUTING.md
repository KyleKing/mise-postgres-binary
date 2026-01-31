# Contributing to mise-postgres-binary

## Development Setup

```sh
# Clone the repository
git clone https://github.com/kyleking/mise-postgres-binary
cd mise-postgres-binary

# Install development tools
mise install

# Interactively see all options
mise run
```

## Testing

### GitHub Token for Development

When developing the plugin, you may frequently clear caches and list versions, which can hit GitHub API rate limits (60 requests/hour unauthenticated).

```sh
export GITHUB_TOKEN=$(gh auth token) # Requires the GitHub CLI

# mise cache clear
# mise ls-remote postgres-binary:postgres | head -5
```

**Note:** both this plugin and mise cache version lists so that end-users do not need to export a token, but doing so for local development, CI, and Docker tests is recommended.

### Local Testing

Ensure plugin is linked for local testing:

```sh
mise plugin link --force postgres-binary "$PWD"
```

Quick test:

```sh
mise ls-remote postgres-binary:postgres | head -10
mise install postgres-binary:postgres@14.20.0
mise exec postgres-binary:postgres@14.20.0 -- postgres --version
```

Full test with database operations:

```sh
mise install postgres-binary:postgres@18.1.0

eval "$(mise activate zsh)"
mise use postgres-binary:postgres@18.1.0

echo "PGDATA: $PGDATA"
ls -la "$PGDATA"

pg_ctl start -D "$PGDATA" -l /tmp/postgres.log -w
psql -c "SELECT version();" postgres
pg_ctl stop -D "$PGDATA" -m fast
```

### Docker Testing

Docker tests verify the plugin works on different Linux distributions. Set `GITHUB_TOKEN` as shown above to avoid rate limits:

```sh
# Build and test all targets
docker buildx bake

# Build specific target
docker buildx bake debian-pg14
docker run --rm mise-postgres-debian-pg14

# View all available targets
docker buildx bake --print
```

See `docker/docker-bake.hcl` for available target groups.

### CI Pipeline

See `.github/workflows/ci.yml` for tested platforms and PostgreSQL versions.

Run CI checks locally:

```sh
mise run lint # Run linters
mise run test # Quick test
mise run ci   # Full CI pipeline
```

## Version Management

PostgreSQL versions are managed via `scripts/postgres-versions.json`. The sync script propagates versions to all dependent files:

```sh
# Check for updates
./scripts/sync-postgres-versions.py --check

# Apply updates
./scripts/sync-postgres-versions.py --apply
```

## Verification Checklist

Before submitting changes:

- [ ] `mise run lint` passes
- [ ] Local installation works: `mise install postgres-binary:postgres@<version>`
- [ ] Binary verification: `postgres --version`, `psql --version`
- [ ] Environment setup: `$PGDATA` exists and is initialized
- [ ] Database operations: can start, query, and stop PostgreSQL
- [ ] Docker tests pass: `docker buildx bake ci`

## Troubleshooting

### Plugin Not Found

```sh
mise plugin uninstall postgres-binary
mise plugin link --force postgres-binary "$PWD"
```

### Version Not Installing

```sh
# List available versions
mise ls-remote postgres-binary:postgres

# Debug installation with detailed output
MISE_DEBUG=1 mise install postgres-binary:postgres@14.20.0

# Save debug output for issue reports
MISE_DEBUG=1 mise install postgres-binary:postgres@14.20.0 2>&1 | tee debug.log
```

### Docker Build Fails

```sh
docker buildx prune -f
docker buildx bake --no-cache debian-pg14
```

## Commits and Versioning

Follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, etc.).
Commits to `main` trigger automatic version bumping via [commitizen](https://commitizen-tools.github.io/commitizen/),

#!/bin/bash
set -euo pipefail

# Read GITHUB_TOKEN from secret mount if available
export GITHUB_TOKEN=$(cat /run/secrets/github_token 2>/dev/null || true)

echo "=== Testing mise-postgres-binary on Alpine (musl) ==="
echo "Platform: $(uname -s) $(uname -m)"
echo "libc: musl"
echo ""

echo "Step 1: List available versions"
mise ls-remote postgres-binary:postgres | head -5
echo ""

echo "Step 2: Install PostgreSQL $POSTGRES_VERSION"
mise install postgres-binary:postgres@$POSTGRES_VERSION
echo ""

echo "Step 3: Verify installation"
mise exec postgres-binary:postgres@$POSTGRES_VERSION -- postgres --version
mise exec postgres-binary:postgres@$POSTGRES_VERSION -- psql --version
mise exec postgres-binary:postgres@$POSTGRES_VERSION -- pg_dump --version
echo ""

echo "Step 4: Check environment"
mise use postgres-binary:postgres@$POSTGRES_VERSION
eval "$(mise activate bash)"
echo "PGDATA=$PGDATA"
[ -d "$PGDATA" ] && echo "PGDATA directory exists" || exit 1
[ -f "$PGDATA/PG_VERSION" ] && echo "Database initialized (PG_VERSION present)" || exit 1
echo ""

echo "Step 5: Start PostgreSQL briefly"
pg_ctl start -D "$PGDATA" -l /tmp/pg.log -w
sleep 2
psql -c "SELECT version();" postgres
pg_ctl stop -D "$PGDATA" -m fast
echo ""

echo "=== All tests passed ==="

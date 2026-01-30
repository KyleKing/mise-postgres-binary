# mise-postgres-binary

mise backend plugin for installing PostgreSQL from pre-built binaries.

## Features

- **Fast installations**: Pre-built binaries, no compilation required
- **Precise version control**: Install specific PostgreSQL versions (e.g., 15.10.0)
- **Secure**: SHA256 checksum verification for all downloads
- **Cross-platform**: macOS (Intel/Apple Silicon), Linux (x86_64/arm64, glibc/musl), Windows
- **PostgreSQL-aware**: Automatic PGDATA setup and initdb execution
- **Low maintenance**: Simple Lua implementation

## Installation

```bash
# Install the backend plugin
mise plugin install postgres-binary https://github.com/kyleking/mise-postgres-binary

# Use in your project
mise use postgres-binary:postgres@14.20.0

# PostgreSQL is now available
postgres --version
psql --version
```

## Usage

### Basic Usage

```bash
# Install a specific PostgreSQL version
mise install postgres-binary:postgres@14.20.0

# Use in current directory
cd my-project
mise use postgres-binary:postgres@14.20.0

# Start PostgreSQL
mise exec -- pg_ctl start -D $PGDATA
```

### Environment Variables

The plugin automatically sets up:

- `PGDATA`: PostgreSQL data directory (auto-initialized with `initdb`)
- `PATH`: Includes PostgreSQL bin directory
- `LD_LIBRARY_PATH`: PostgreSQL lib directory (Linux)
- `DYLD_LIBRARY_PATH`: PostgreSQL lib directory (macOS)
- `PGHOME`: PostgreSQL installation directory

### Database Initialization

The plugin automatically runs `initdb` on first installation, creating a database cluster in `$PGDATA`.

### Version Caching

mise caches available version lists (~1 hour default TTL). The plugin adds an
ETag-based HTTP cache layer (12-hour TTL) at XDG-compliant paths to further
reduce GitHub API calls.

- Override TTL: `export MISE_POSTGRES_BINARY_CACHE_TTL=3600` (seconds; 0 disables)
- Clear mise cache: `mise cache clear`
- CI: `jdx/mise-action` automatically provides `GITHUB_TOKEN`

## Supported Platforms

Binaries are sourced from [theseus-rs/postgresql-binaries](https://github.com/theseus-rs/postgresql-binaries):

| Platform | Architecture | Target Triple |
|----------|--------------|---------------|
| macOS | Intel (x86_64) | `x86_64-apple-darwin` |
| macOS | Apple Silicon (M1/M2) | `aarch64-apple-darwin` |
| Linux | x86_64 (glibc) | `x86_64-unknown-linux-gnu` |
| Linux | ARM64 (glibc) | `aarch64-unknown-linux-gnu` |
| Linux | x86_64 (musl) | `x86_64-unknown-linux-musl` |
| Linux | ARM64 (musl) | `aarch64-unknown-linux-musl` |
| Windows | x86_64 | `x86_64-pc-windows-msvc` |

## Supported PostgreSQL Versions

- PostgreSQL 18.x
- PostgreSQL 17.x
- PostgreSQL 16.x
- PostgreSQL 15.x
- PostgreSQL 14.x
- PostgreSQL 13.x

See [theseus-rs/postgresql-binaries releases](https://github.com/theseus-rs/postgresql-binaries/releases) for the complete list.

## How It Works

1. **Version Discovery**: Queries GitHub API for available PostgreSQL releases
2. **Platform Detection**: Detects OS and architecture to select correct binary
3. **libc Detection**: On Linux, detects glibc vs musl
4. **Download & Verify**: Fetches binary and verifies SHA256 checksum
5. **Initialization**: Runs `initdb` to create PostgreSQL data directory
6. **Environment Setup**: Configures PGDATA, PATH, and library paths

## Comparison with Source Builds

| Feature | Binary Installation | Source Build |
|---------|-------------------|--------------|
| **Installation Time** | ~10 seconds | ~5-15 minutes |
| **Build Dependencies** | None | gcc, make, openssl-dev, etc. |
| **Platform Patches** | Not needed | ICU, UUID-OSSP patches |
| **Disk Space** | ~50 MB | ~200+ MB (with build files) |
| **Customization** | Pre-built config | Full control via ./configure |

## Troubleshooting

### Unsupported Platform

If you see "Unsupported platform" error, check:

1. Your OS and architecture: `uname -s` and `uname -m`
2. Available platforms in [theseus-rs releases](https://github.com/theseus-rs/postgresql-binaries/releases)
3. Consider using the source-based [mise-postgres](https://github.com/kyleking/mise-postgres) plugin

### SHA256 Verification Failed

This usually indicates a corrupted download. Try:

1. Remove the installation: `mise uninstall postgres-binary:postgres@<version>`
2. Clear mise cache: `rm -rf ~/.local/share/mise/downloads/postgres-binary*`
3. Reinstall: `mise install postgres-binary:postgres@<version>`

### Database Already Initialized

If you see "PGDATA directory already exists", the database cluster is already initialized. This is normal and safe.

### PostgreSQL Won't Start

Check logs and port availability:

```bash
cat /tmp/postgres.log
lsof -i :5432
pg_ctl start -D "$PGDATA" -o "-p 5433" -l /tmp/postgres.log  # Use alternate port
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

MIT License - see LICENSE file for details

## Credits

- Binaries provided by [theseus-rs/postgresql-binaries](https://github.com/theseus-rs/postgresql-binaries)
- Plugin template from [mise-backend-plugin-template](https://github.com/jdx/mise-backend-plugin-template)
- Inspired by [mise-postgres](https://github.com/kyleking/mise-postgres) (source-based)

## Links

- [mise documentation](https://mise.jdx.dev/)
- [Backend plugin development guide](https://mise.jdx.dev/backend-plugin-development.html)
- [PostgreSQL official documentation](https://www.postgresql.org/docs/)

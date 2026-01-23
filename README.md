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
mise plugin install postgres-binary https://github.com/mise-plugins/mise-postgres-binary

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

## Development

### Setup

```bash
# Clone the repository
git clone https://github.com/mise-plugins/mise-postgres-binary
cd mise-postgres-binary

# Install development tools
mise install

# Link plugin for local testing
mise plugin link --force postgres-binary "$PWD"
```

### Available Tasks

```bash
mise run format       # Format Lua code with stylua
mise run lint         # Run all linters (luacheck, stylua, actionlint)
mise run test         # Quick test (link plugin, list versions)
mise run test-install # Full test with database operations
mise run test-docker  # Run Docker-based tests
mise run ci           # Full CI pipeline (lint + test)
mise run clean        # Clean up test installations
```

### Testing

See [TESTING.md](TESTING.md) for comprehensive testing instructions including:

- Local testing on macOS/Linux
- Docker testing (Debian glibc, Alpine musl)
- CI verification

Quick local test:

```bash
# Link and install
mise plugin link --force postgres-binary "$PWD"
mise install postgres-binary:postgres@14.20.0

# Verify
mise exec postgres-binary:postgres@14.20.0 -- postgres --version
```

Docker test:

```bash
# Run all Docker tests (using Docker Buildx Bake)
./test/run-docker-tests.sh

# Or specific target group
./test/run-docker-tests.sh debian
./test/run-docker-tests.sh alpine
./test/run-docker-tests.sh ci
```

### Project Structure

```
mise-postgres-binary/
├── hooks/
│   ├── backend_list_versions.lua  # Fetch versions from GitHub API
│   ├── backend_install.lua        # Download, verify, extract, initdb
│   └── backend_exec_env.lua       # Set environment variables
├── test/
│   ├── Dockerfile.debian          # Debian (glibc) test container
│   ├── Dockerfile.alpine          # Alpine (musl) test container
│   └── run-docker-tests.sh        # Docker test runner
├── .github/workflows/ci.yml       # CI/CD pipeline
├── .luacheckrc                    # Lua linter configuration
├── docker-bake.hcl                # Docker Buildx Bake configuration
├── hk.pkl                         # Pre-commit hooks
├── mise.toml                      # Development tools and tasks
├── metadata.lua                   # Plugin metadata
├── stylua.toml                    # Lua formatter configuration
├── TESTING.md                     # Testing documentation
└── README.md
```

## How It Works

1. **Version Discovery**: Queries GitHub API for available PostgreSQL releases
2. **Platform Detection**: Uses `RUNTIME.osType` and `RUNTIME.archType` to determine platform
3. **libc Detection**: On Linux, detects glibc vs musl to select correct binary
4. **Download**: Fetches platform-specific binary tarball from GitHub releases
5. **Verification**: Downloads SHA256 checksum and verifies binary integrity
6. **Extraction**: Extracts tarball to installation directory
7. **Initialization**: Runs `initdb` to create PostgreSQL data directory
8. **Environment Setup**: Configures PGDATA, PATH, and library paths

## Security

- All downloads are verified using SHA256 checksums
- Checksums are fetched from GitHub releases (`.sha256` files)
- mise's built-in `http.download_file` function performs automatic verification

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
3. Consider using the source-based [mise-postgres](https://github.com/mise-plugins/mise-postgres) plugin

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

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Run `mise run lint` before committing
4. Run `mise run test-install` to verify changes
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Credits

- Binaries provided by [theseus-rs/postgresql-binaries](https://github.com/theseus-rs/postgresql-binaries)
- Plugin template from [mise-backend-plugin-template](https://github.com/jdx/mise-backend-plugin-template)
- Inspired by [mise-postgres](https://github.com/mise-plugins/mise-postgres) (source-based)

## Links

- [mise documentation](https://mise.jdx.dev/)
- [Backend plugin development guide](https://mise.jdx.dev/backend-plugin-development.html)
- [PostgreSQL official documentation](https://www.postgresql.org/docs/)

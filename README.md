# mise-postgres-binary

mise backend plugin for installing PostgreSQL from pre-built binaries. Fast cross-platform installs with SHA256 verification and automatic PGDATA setup -- no compiler toolchain needed. Use a source-build plugin like [mise-postgres](https://github.com/kyleking/mise-postgres) if you need custom `./configure` options.

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

## Supported Platforms

Binaries are sourced from [theseus-rs/postgresql-binaries](https://github.com/theseus-rs/postgresql-binaries). See [their releases](https://github.com/theseus-rs/postgresql-binaries/releases) for the latest supported versions and platforms.

| Platform | Architecture | Target Triple |
|----------|--------------|---------------|
| macOS | Intel (x86_64) | `x86_64-apple-darwin` |
| macOS | Apple Silicon (M1/M2) | `aarch64-apple-darwin` |
| Linux | x86_64 (glibc) | `x86_64-unknown-linux-gnu` |
| Linux | ARM64 (glibc) | `aarch64-unknown-linux-gnu` |
| Linux | x86_64 (musl) | `x86_64-unknown-linux-musl` |
| Linux | ARM64 (musl) | `aarch64-unknown-linux-musl` |
| Windows | x86_64 | `x86_64-pc-windows-msvc` |

### System Dependencies

SHA256 checksum verification requires platform-specific tools:

**Unix/Linux/macOS:**
- `sha256sum` (GNU coreutils) OR `shasum` (macOS/BSD)
- `awk` (standard on all systems)

**Windows:**
- **Primary**: Unix tools via Git Bash (Git for Windows, MSYS2, Cygwin)
  - `sha256sum`, `awk` - provided by Git for Windows
- **Fallback 1**: PowerShell (Windows 7+)
  - `Get-FileHash` cmdlet (PowerShell 4.0+)
- **Fallback 2**: `certutil.exe` (Windows Vista+)

The plugin tries Unix tools first (works everywhere including Git Bash on Windows), then falls back to Windows-specific tools if needed.

**Skip Checksum Validation (Not Recommended):**

If none of the hash tools are available, you can skip checksum verification:

```sh
export MISE_POSTGRES_BINARY_SKIP_CHECKSUM=1
```

**WARNING**: Skipping checksum validation is insecure and not recommended. Use only in environments where hash tools cannot be installed and you trust the network connection.

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

If hash tools are unavailable in your environment, you can skip validation (insecure):

```sh
export MISE_POSTGRES_BINARY_SKIP_CHECKSUM=1
mise install postgres-binary:postgres@<version>
```

### Database Already Initialized

If you see "PGDATA directory already exists", the database cluster is already initialized. This is normal and safe.

### PostgreSQL Won't Start

Check logs and port availability:

```sh
cat /tmp/postgres.log
lsof -i :5432
pg_ctl start -D "$PGDATA" -o "-p 5433" -l /tmp/postgres.log # Use alternate port
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## Credits

- Binaries provided by [theseus-rs/postgresql-binaries](https://github.com/theseus-rs/postgresql-binaries)
- Plugin template from [mise-backend-plugin-template](https://github.com/jdx/mise-backend-plugin-template)
- Inspired by [mise-postgres](https://github.com/kyleking/mise-postgres) (source-based)

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-01-30

### Added
- Initial release of mise-postgres-binary plugin
- Fast PostgreSQL installations from pre-built binaries
- Support for PostgreSQL 13+ versions
- Cross-platform support (macOS, Linux, Windows)
- SHA256 checksum verification
- Automatic PGDATA initialization
- Dynamic version discovery via GitHub API
- Automated test version updates

### Features
- Pre-compiled binaries from theseus-rs/postgresql-binaries
- Automatic environment variable setup (PGDATA, PATH, etc.)
- GitHub API rate limit handling with token support
- Pagination and early exit optimization for version listing
- Platform detection (glibc/musl on Linux)

[Unreleased]: https://github.com/kyleking/mise-postgres-binary/compare/1.0.0...HEAD
[1.0.0]: https://github.com/kyleking/mise-postgres-binary/releases/tag/1.0.0

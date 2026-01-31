# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-01-30

### Added
- Initial release of mise-postgres-binary plugin
- Automatic environment variable setup (PGDATA, PATH, etc.)
- Automatic PGDATA initialization
- Cross-platform support (macOS, Linux, Windows)
- Dynamic version discovery via GitHub API with pagination and early exit
- Fast PostgreSQL installations from pre-built binaries (theseus-rs/postgresql-binaries)
- GitHub API rate limit handling with token support
- Platform detection (glibc/musl on Linux)
- SHA256 checksum verification
- Support for PostgreSQL 13+ versions

[Unreleased]: https://github.com/kyleking/mise-postgres-binary/compare/1.0.0...HEAD
[1.0.0]: https://github.com/kyleking/mise-postgres-binary/releases/tag/1.0.0

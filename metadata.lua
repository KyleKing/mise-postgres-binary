PLUGIN = {
    name = "mise-postgres-binary",
    author = "kyleking",
    version = "1.0.0",
    license = "MIT",
    description = "mise backend plugin for PostgreSQL binaries from theseus-rs/postgresql-binaries",
    source_url = "https://github.com/kyleking/mise-postgres-binary",
    notes = {
        "Supports PostgreSQL versions 13+",
        "Binaries sourced from https://github.com/theseus-rs/postgresql-binaries",
        "Supported platforms: macOS (x86_64/arm64), Linux (x86_64/arm64, glibc/musl), Windows",
        "Automatically initializes PGDATA and sets up environment variables",
    },
}

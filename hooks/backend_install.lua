local cmd = require("cmd")
local file = require("file")
local http = require("http")
local archiver = require("archiver")

local RUST_TARGETS = {
    ["darwin-amd64"] = "x86_64-apple-darwin",
    ["darwin-arm64"] = "aarch64-apple-darwin",
    ["linux-amd64-gnu"] = "x86_64-unknown-linux-gnu",
    ["linux-amd64-musl"] = "x86_64-unknown-linux-musl",
    ["linux-arm64-gnu"] = "aarch64-unknown-linux-gnu",
    ["linux-arm64-musl"] = "aarch64-unknown-linux-musl",
    ["linux-386-gnu"] = "i686-unknown-linux-gnu",
    ["linux-386-musl"] = "i686-unknown-linux-musl",
    ["windows-amd64"] = "x86_64-pc-windows-msvc",
}

local function parse_sha256_from_output(output)
    if not output then
        return nil
    end
    for hex_sequence in output:gmatch("%x+") do
        if #hex_sequence == 64 then
            return hex_sequence:lower()
        end
    end
    return nil
end

local function lookup_rust_target(os_type, arch_type, is_musl)
    if os_type == "linux" then
        local suffix = is_musl and "musl" or "gnu"
        return RUST_TARGETS[os_type .. "-" .. arch_type .. "-" .. suffix]
    end
    return RUST_TARGETS[os_type .. "-" .. arch_type]
end

local function normalize_path(path, os_type)
    if not path then
        return nil
    end
    if os_type == "windows" then
        return path:gsub("/", "\\")
    end
    return path
end

local function is_musl_libc()
    local result = cmd.exec("ldd --version 2>&1 || true")
    if result and result:match("musl") then
        return true
    end
    if file.exists("/etc/alpine-release") then
        return true
    end
    return false
end

local function get_rust_target()
    local os_type = RUNTIME.osType:lower()
    local arch_type = RUNTIME.archType
    local is_musl = os_type == "linux" and is_musl_libc() or false

    local target = lookup_rust_target(os_type, arch_type, is_musl)
    if not target then
        error(
            string.format(
                "Unsupported platform: %s-%s\nSupported: macOS (x86_64/arm64), Linux (x86_64/arm64/i686, glibc/musl), Windows (x86_64)",
                os_type,
                arch_type
            )
        )
    end
    return target
end

--- Downloads PostgreSQL binary with SHA256 checksum verification
--- @param version string PostgreSQL version (e.g., "15.10.0")
--- @param platform string Rust target triple
--- @param install_path string Destination directory
local function download_and_verify_postgresql(version, platform, install_path)
    local base_url = string.format("https://github.com/theseus-rs/postgresql-binaries/releases/download/%s", version)

    local filename = string.format("postgresql-%s-%s.tar.gz", version, platform)
    local download_url = base_url .. "/" .. filename
    local checksum_url = download_url .. ".sha256"
    local temp_archive = install_path .. "/" .. filename

    local checksum_resp, checksum_err = http.get({ url = checksum_url })
    if checksum_err then
        error("Failed to download checksum file: " .. tostring(checksum_err))
    end

    local expected_sha256 = parse_sha256_from_output(checksum_resp.body)
    if not expected_sha256 then
        error("Invalid checksum format in file (expected 64-char SHA256): " .. checksum_resp.body)
    end

    local download_err = http.download_file({
        url = download_url,
    }, temp_archive)

    if download_err then
        error("Failed to download PostgreSQL binary: " .. tostring(download_err))
    end

    local os_type = RUNTIME.osType:lower()
    local checksum_cmd = string.format(
        '(sha256sum "%s" 2>/dev/null || shasum -a 256 "%s" 2>/dev/null) | awk \'{print $1}\'',
        temp_archive,
        temp_archive
    )

    local checksum_output = cmd.exec(checksum_cmd)
    local computed_sha256 = parse_sha256_from_output(checksum_output)

    if not computed_sha256 and os_type == "windows" then
        local win_path = normalize_path(temp_archive, os_type)
        local certutil_cmd = string.format('certutil -hashfile "%s" SHA256', win_path)
        local ok, certutil_output = pcall(cmd.exec, certutil_cmd)
        if ok then
            computed_sha256 = parse_sha256_from_output(certutil_output)
        end
    end

    if not computed_sha256 then
        error("Failed to compute SHA256 checksum for: " .. temp_archive)
    end

    if computed_sha256 ~= expected_sha256 then
        os.remove(temp_archive)
        error(string.format("SHA256 mismatch! Expected: %s, Got: %s", expected_sha256, computed_sha256))
    end

    local extract_err = archiver.decompress(temp_archive, install_path)
    if extract_err then
        os.remove(temp_archive)
        error("Failed to extract archive: " .. tostring(extract_err))
    end

    local extracted_dir = string.format("%s/postgresql-%s-%s", install_path, version, platform)
    local move_cmd =
        string.format('sh -c \'cp -r "%s"/* "%s/" && rm -rf "%s"\'', extracted_dir, install_path, extracted_dir)
    cmd.exec(move_cmd)

    os.remove(temp_archive)
end

--- Initializes PostgreSQL data directory (PGDATA) using initdb
--- @param install_path string PostgreSQL installation directory
local function initialize_pgdata(install_path)
    local os_type = RUNTIME.osType:lower()
    local pgdata_dir = install_path .. "/data"

    if file.exists(pgdata_dir) then
        print("PGDATA directory already exists, skipping initdb")
        return
    end

    print("Initializing PostgreSQL data directory at: " .. pgdata_dir)

    local initdb_bin = install_path .. "/bin/initdb"
    if os_type == "windows" then
        initdb_bin = initdb_bin .. ".exe"
    end

    if not file.exists(initdb_bin) then
        error("initdb binary not found at: " .. initdb_bin)
    end

    local initdb_cmd = string.format('"%s" -D "%s" --encoding=UTF8 --locale=C', initdb_bin, pgdata_dir)
    local result = cmd.exec(initdb_cmd)

    if result:match("error") or result:match("failed") then
        error("Failed to initialize PostgreSQL data directory: " .. result)
    end

    print("Database cluster initialized successfully")
end

--- Installs PostgreSQL from pre-built binaries with platform detection and SHA256 verification
--- @param ctx table Context containing tool, version, and install_path
--- @return table Empty table on success
function PLUGIN:BackendInstall(ctx)
    local tool = ctx.tool
    local version = ctx.version
    local install_path = ctx.install_path

    if not tool or tool == "" then
        error("Tool name is required")
    end
    if not version or version == "" then
        error("Version is required")
    end
    if not install_path or install_path == "" then
        error("Install path is required")
    end

    if tool ~= "postgres" and tool ~= "postgresql" then
        error("This backend only supports 'postgres' or 'postgresql' tools")
    end

    if not file.exists(install_path) then
        cmd.exec('mkdir -p "' .. install_path .. '"')
    end

    local platform_target = get_rust_target()
    print("Installing PostgreSQL " .. version .. " for platform: " .. platform_target)

    download_and_verify_postgresql(version, platform_target, install_path)

    initialize_pgdata(install_path)

    print("PostgreSQL " .. version .. " installed successfully at " .. install_path)
    return {}
end

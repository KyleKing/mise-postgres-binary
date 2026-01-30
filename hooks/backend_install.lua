local cmd = require("cmd")
local file = require("file")
local http = require("http")
local archiver = require("archiver")

--- Detects if the system uses musl libc (Alpine Linux, etc.)
--- @return boolean True if musl libc is detected
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

--- Maps RUNTIME platform to Rust target triple used by theseus-rs/postgresql-binaries
--- @return string Rust target triple (e.g., "x86_64-apple-darwin")
local function get_rust_target()
    local os_type = RUNTIME.osType:lower()
    local arch_type = RUNTIME.archType

    if os_type == "darwin" then
        if arch_type == "amd64" then
            return "x86_64-apple-darwin"
        elseif arch_type == "arm64" then
            return "aarch64-apple-darwin"
        end
    elseif os_type == "linux" then
        local use_musl = is_musl_libc()
        local libc_suffix = use_musl and "musl" or "gnu"

        if arch_type == "amd64" then
            return "x86_64-unknown-linux-" .. libc_suffix
        elseif arch_type == "arm64" then
            return "aarch64-unknown-linux-" .. libc_suffix
        elseif arch_type == "386" then
            return "i686-unknown-linux-" .. libc_suffix
        end
    elseif os_type == "windows" then
        if arch_type == "amd64" then
            return "x86_64-pc-windows-msvc"
        end
    end

    error(
        string.format(
            "Unsupported platform: %s-%s\nSupported: macOS (x86_64/arm64), Linux (x86_64/arm64/i686, glibc/musl), Windows (x86_64)",
            os_type,
            arch_type
        )
    )
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

    print("Downloading checksum from: " .. checksum_url)

    -- Download and parse SHA256 checksum file
    local checksum_resp, checksum_err = http.get({ url = checksum_url })
    if checksum_err then
        error("Failed to download checksum file: " .. tostring(checksum_err))
    end

    -- Parse checksum from file
    -- The file may contain just the hash, or it may contain CertUtil output format:
    -- "SHA256 hash of file:\n<hash>\nCertUtil: -hashfile command completed successfully."
    -- Extract any sequence of exactly 64 hex characters (SHA256 hash length)
    local expected_sha256 = checksum_resp.body:match(
        "(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)"
    )
    if not expected_sha256 or #expected_sha256 ~= 64 then
        error("Invalid checksum format in file (expected 64-char SHA256): " .. checksum_resp.body)
    end

    print("Expected SHA256: " .. expected_sha256)
    print("Downloading PostgreSQL binary from: " .. download_url)

    -- Download the PostgreSQL binary
    local download_err = http.download_file({
        url = download_url,
    }, temp_archive)

    if download_err then
        error("Failed to download PostgreSQL binary: " .. tostring(download_err))
    end

    -- Verify SHA256 checksum (cross-platform)
    local os_type = RUNTIME.osType:lower()
    local checksum_cmd
    if os_type == "windows" then
        -- Windows: Use CertUtil which works reliably in Git Bash
        -- CertUtil outputs format:
        -- SHA256 hash of <file>:
        -- <hash>
        -- CertUtil: -hashfile command completed successfully.
        checksum_cmd = string.format('certutil -hashfile "%s" SHA256', temp_archive)
    else
        -- Unix: Use sha256sum or shasum
        checksum_cmd = string.format(
            '(sha256sum "%s" 2>/dev/null || shasum -a 256 "%s") | awk \'{print $1}\'',
            temp_archive,
            temp_archive
        )
    end

    -- Execute command and parse output
    print("Executing checksum command: " .. checksum_cmd)
    local checksum_output = cmd.exec(checksum_cmd)
    
    if not checksum_output or checksum_output == "" then
        error("Failed to compute checksum - command returned empty output")
    end
    
    local computed_sha256
    
    if os_type == "windows" then
        -- Parse CertUtil output - extract 64-character hex string
        print("CertUtil output: " .. checksum_output)
        computed_sha256 = checksum_output:match("(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)")
        if not computed_sha256 then
            error("Failed to parse CertUtil output. Expected to find 64-character SHA256 hash. Output was: " .. checksum_output)
        end
    else
        -- Unix output is already the hash
        computed_sha256 = checksum_output
    end
    
    -- Normalize both checksums: remove whitespace and convert to lowercase
    computed_sha256 = (computed_sha256 or ""):gsub("%s+", ""):lower()
    local expected_sha256_normalized = expected_sha256:gsub("%s+", ""):lower()

    if computed_sha256 ~= expected_sha256_normalized then
        os.remove(temp_archive)
        error(string.format("SHA256 mismatch! Expected: %s, Got: %s", expected_sha256_normalized, computed_sha256))
    end

    print("Download complete, SHA256 verified")
    print("Extracting archive...")

    -- Extract the archive to install_path
    local extract_err = archiver.decompress(temp_archive, install_path)
    if extract_err then
        os.remove(temp_archive)
        error("Failed to extract archive: " .. tostring(extract_err))
    end

    -- The archive contains a top-level directory (e.g., postgresql-15.15.0-aarch64-apple-darwin/)
    -- We need to move its contents up one level to install_path
    local extracted_dir = string.format("%s/postgresql-%s-%s", install_path, version, platform)

    -- Move contents from extracted directory to install_path
    -- This works on both Unix and Git Bash on Windows
    -- Use sh -c to ensure proper glob expansion with quoted paths
    local move_cmd =
        string.format('sh -c \'cp -r "%s"/* "%s/" && rm -rf "%s"\'', extracted_dir, install_path, extracted_dir)
    cmd.exec(move_cmd)

    -- Clean up archive file
    os.remove(temp_archive)

    print("Extraction complete")
end

--- Initializes PostgreSQL data directory (PGDATA) using initdb
--- @param install_path string PostgreSQL installation directory
local function initialize_pgdata(install_path)
    local os_type = RUNTIME.osType:lower()
    local pgdata_dir = install_path .. "/data"

    -- Check if data directory already exists
    if file.exists(pgdata_dir) then
        print("PGDATA directory already exists, skipping initdb")
        return
    end

    print("Initializing PostgreSQL data directory at: " .. pgdata_dir)

    -- Handle Windows .exe extension
    local initdb_bin = install_path .. "/bin/initdb"
    if os_type == "windows" then
        initdb_bin = initdb_bin .. ".exe"
    end

    -- Check if initdb exists (it should after extraction)
    if not file.exists(initdb_bin) then
        error("initdb binary not found at: " .. initdb_bin)
    end

    -- Run initdb to initialize the database cluster
    -- Use UTF-8 encoding and C locale for maximum compatibility
    -- Quote paths for Windows compatibility
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

    -- Validate inputs
    if not tool or tool == "" then
        error("Tool name is required")
    end
    if not version or version == "" then
        error("Version is required")
    end
    if not install_path or install_path == "" then
        error("Install path is required")
    end

    -- Only handle postgres/postgresql tools
    if tool ~= "postgres" and tool ~= "postgresql" then
        error("This backend only supports 'postgres' or 'postgresql' tools")
    end

    -- Create installation directory if it doesn't exist
    if not file.exists(install_path) then
        cmd.exec('mkdir -p "' .. install_path .. '"')
    end

    -- Detect platform and get Rust target triple
    local platform_target = get_rust_target()
    print("Installing PostgreSQL " .. version .. " for platform: " .. platform_target)

    -- Download and verify PostgreSQL binary
    download_and_verify_postgresql(version, platform_target, install_path)

    -- Initialize PostgreSQL data directory
    initialize_pgdata(install_path)

    print("PostgreSQL " .. version .. " installed successfully at " .. install_path)
    return {}
end

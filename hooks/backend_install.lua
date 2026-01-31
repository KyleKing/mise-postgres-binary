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

--- Computes SHA256 checksum using platform-appropriate tools
--- @param filepath string Path to file (forward or backward slashes)
--- @param os_type string Operating system type from RUNTIME.osType
--- @return string|nil SHA256 hash (64-char lowercase hex string), or nil if skipped
local function compute_sha256(filepath, os_type)
    if not file.exists(filepath) then
        error(string.format("Cannot compute checksum: file does not exist: %s", filepath))
    end

    local diagnostics = {
        unix = { attempted = false, success = false, error = nil, output = nil, command = nil },
        powershell = { attempted = false, success = false, error = nil, output = nil, command = nil },
        certutil = { attempted = false, success = false, error = nil, output = nil, command = nil },
    }

    if os_type ~= "windows" then
        local unix_cmd = string.format(
            '(sha256sum "%s" 2>/dev/null || shasum -a 256 "%s" 2>/dev/null) | awk \'{print $1}\'',
            filepath,
            filepath
        )
        diagnostics.unix.attempted = true
        diagnostics.unix.command = unix_cmd

        local output = cmd.exec(unix_cmd)
        if output and output ~= "" then
            diagnostics.unix.output = output
            local hash = parse_sha256_from_output(output)
            if hash then
                diagnostics.unix.success = true
                return hash
            else
                diagnostics.unix.error = "Command succeeded but output did not contain valid SHA256 hash"
            end
        else
            diagnostics.unix.error = "Command returned empty output"
        end
    end

    if os_type == "windows" then
        local ps_cmd = string.format(
            "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"(Get-FileHash -Algorithm SHA256 -Path '%s').Hash\"",
            filepath:gsub("\\", "/")
        )
        diagnostics.powershell.attempted = true
        diagnostics.powershell.command = ps_cmd

        local ps_output = cmd.exec(ps_cmd)
        if ps_output and ps_output ~= "" then
            diagnostics.powershell.output = ps_output
            local hash = parse_sha256_from_output(ps_output)
            if hash then
                diagnostics.powershell.success = true
                return hash
            else
                diagnostics.powershell.error = "PowerShell executed but output did not contain valid SHA256 hash"
            end
        else
            diagnostics.powershell.error = "PowerShell returned empty output"
        end

        local certutil_cmd = string.format('certutil.exe -hashfile "%s" SHA256', filepath:gsub("\\", "/"))
        diagnostics.certutil.attempted = true
        diagnostics.certutil.command = certutil_cmd

        local certutil_output = cmd.exec(certutil_cmd)
        if certutil_output and certutil_output ~= "" then
            diagnostics.certutil.output = certutil_output
            local hash = parse_sha256_from_output(certutil_output)
            if hash then
                diagnostics.certutil.success = true
                return hash
            else
                diagnostics.certutil.error = "certutil executed but output did not contain valid SHA256 hash"
            end
        else
            diagnostics.certutil.error = "certutil returned empty output"
        end

        local skip_checksum = os.getenv("MISE_POSTGRES_BINARY_SKIP_CHECKSUM")
        if skip_checksum == "1" or skip_checksum == "true" then
            print(
                "WARNING: Skipping SHA256 verification (MISE_POSTGRES_BINARY_SKIP_CHECKSUM=1). This is insecure and not recommended."
            )
            print("\nDiagnostics for failed checksum attempts:")
            print(string.format("  File: %s", filepath))
            for method, info in pairs(diagnostics) do
                if info.attempted then
                    print(string.format("\n  Method: %s", method))
                    print(string.format("    Command: %s", info.command or "N/A"))
                    print(string.format("    Success: %s", tostring(info.success)))
                    print(string.format("    Error: %s", info.error or "N/A"))
                    if info.output and #info.output > 0 and #info.output < 500 then
                        print(string.format("    Output: %s", info.output))
                    elseif info.output and #info.output >= 500 then
                        print(string.format("    Output: [%d bytes, truncated]", #info.output))
                    end
                end
            end
            return nil
        end

        local error_msg = {
            "Failed to compute SHA256 checksum on Windows. All methods failed.",
            string.format("\nFile: %s", filepath),
            string.format("File exists: %s", tostring(file.exists(filepath))),
            "\nAttempted methods:",
        }

        for method, info in pairs(diagnostics) do
            if info.attempted then
                table.insert(error_msg, string.format("\n%s:", method))
                table.insert(error_msg, string.format("  Command: %s", info.command or "N/A"))
                table.insert(error_msg, string.format("  Error: %s", info.error or "N/A"))
                if info.output and #info.output > 0 and #info.output < 200 then
                    table.insert(error_msg, string.format("  Output: %s", info.output))
                end
            end
        end

        table.insert(error_msg, "\n\nTroubleshooting:")
        table.insert(error_msg, "  - For Git Bash users: Ensure Git for Windows is installed (includes Unix tools)")
        table.insert(error_msg, "  - For PowerShell users: Requires PowerShell 4.0+ (Windows 8.1+)")
        table.insert(error_msg, "  - To skip validation (insecure): export MISE_POSTGRES_BINARY_SKIP_CHECKSUM=1")
        error(table.concat(error_msg, "\n"))
    end

    local skip_checksum = os.getenv("MISE_POSTGRES_BINARY_SKIP_CHECKSUM")
    if skip_checksum == "1" or skip_checksum == "true" then
        print(
            "WARNING: Skipping SHA256 verification (MISE_POSTGRES_BINARY_SKIP_CHECKSUM=1). This is insecure and not recommended."
        )
        print(string.format("\nDiagnostic - Unix tools attempt:"))
        print(string.format("  Command: %s", diagnostics.unix.command))
        print(string.format("  Error: %s", diagnostics.unix.error or "N/A"))
        if diagnostics.unix.output and #diagnostics.unix.output < 200 then
            print(string.format("  Output: %s", diagnostics.unix.output))
        end
        return nil
    end

    local error_msg = {
        "Failed to compute SHA256 checksum. Unix tools (sha256sum/shasum) not available or failed.",
        string.format("\nFile: %s", filepath),
        string.format("File exists: %s", tostring(file.exists(filepath))),
        string.format("\nCommand attempted: %s", diagnostics.unix.command),
        string.format("Error: %s", diagnostics.unix.error or "N/A"),
    }

    if diagnostics.unix.output and #diagnostics.unix.output < 200 then
        table.insert(error_msg, string.format("Output: %s", diagnostics.unix.output))
    end

    table.insert(error_msg, "\n\nTroubleshooting:")
    table.insert(error_msg, "  - Ensure sha256sum (Linux) or shasum (macOS) is installed and in PATH")
    table.insert(error_msg, "  - To skip validation (insecure): export MISE_POSTGRES_BINARY_SKIP_CHECKSUM=1")
    error(table.concat(error_msg, "\n"))
end

local function is_musl_libc()
    local result = cmd.exec("ldd --version 2>&1 || true")
    if result and result ~= "" then
        if result:match("musl") then
            return true
        end
        if result:match("GLIBC") or result:match("glibc") then
            return false
        end
    end

    if file.exists("/etc/alpine-release") then
        return true
    end

    if file.exists("/lib/libc.musl-x86_64.so.1") or file.exists("/lib/ld-musl-x86_64.so.1") then
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
        local libc_info = ""
        if os_type == "linux" then
            libc_info = string.format(" (%s)", is_musl and "musl" or "glibc")
        end

        local error_msg = {
            "Unsupported platform configuration.",
            string.format("\nDetected platform: %s-%s%s", os_type, arch_type, libc_info),
            "\nSupported platforms:",
            "  macOS:",
            "    - x86_64 (Intel)",
            "    - arm64 (Apple Silicon)",
            "  Linux:",
            "    - x86_64 (glibc or musl)",
            "    - arm64 (glibc or musl)",
            "    - i686/386 (glibc or musl)",
            "  Windows:",
            "    - x86_64 (MSVC)",
            "\nIf you believe this platform should be supported, please file an issue at:",
            "https://github.com/theseus-rs/postgresql-binaries/issues",
        }
        error(table.concat(error_msg, "\n"))
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

    print(string.format("Downloading checksum from: %s", checksum_url))
    local checksum_resp, checksum_err = http.get({ url = checksum_url })
    if checksum_err then
        local error_msg = {
            "Failed to download checksum file.",
            string.format("\nURL: %s", checksum_url),
            string.format("Error: %s", tostring(checksum_err)),
            "\nPossible causes:",
            "  - Version does not exist (check available versions at GitHub releases)",
            "  - Network connectivity issues",
            "  - GitHub API rate limiting",
        }
        error(table.concat(error_msg, "\n"))
    end

    local expected_sha256 = parse_sha256_from_output(checksum_resp.body)
    if not expected_sha256 then
        local error_msg = {
            "Invalid checksum format in downloaded checksum file.",
            string.format("\nURL: %s", checksum_url),
            string.format("Expected: 64-character SHA256 hash"),
            string.format("Received: %s", checksum_resp.body),
            "\nThis may indicate:",
            "  - Corrupted checksum file on GitHub",
            "  - Network interception or modification",
        }
        error(table.concat(error_msg, "\n"))
    end

    print(string.format("Expected SHA256: %s", expected_sha256))
    print(string.format("Downloading PostgreSQL binary from: %s", download_url))

    local download_err = http.download_file({
        url = download_url,
    }, temp_archive)

    if download_err then
        local error_msg = {
            "Failed to download PostgreSQL binary archive.",
            string.format("\nURL: %s", download_url),
            string.format("Destination: %s", temp_archive),
            string.format("Error: %s", tostring(download_err)),
            "\nPossible causes:",
            "  - Network connectivity issues",
            "  - Insufficient disk space",
            "  - Permission issues writing to install directory",
        }
        error(table.concat(error_msg, "\n"))
    end

    if not file.exists(temp_archive) then
        error(
            string.format(
                "Download reported success but file not found at: %s\nThis may indicate a bug in the download function.",
                temp_archive
            )
        )
    end

    print(string.format("Downloaded archive: %s", temp_archive))
    print("Verifying checksum...")

    local os_type = RUNTIME.osType:lower()
    local computed_sha256 = compute_sha256(temp_archive, os_type)

    if computed_sha256 then
        print(string.format("Computed SHA256: %s", computed_sha256))
        if computed_sha256 ~= expected_sha256 then
            os.remove(temp_archive)
            local error_msg = {
                "SHA256 checksum mismatch! Downloaded file is corrupted or has been tampered with.",
                string.format("\nFile: %s", temp_archive),
                string.format("Expected: %s", expected_sha256),
                string.format("Computed: %s", computed_sha256),
                "\nThe corrupted archive has been deleted.",
                "This may indicate:",
                "  - Network corruption during download",
                "  - Man-in-the-middle attack",
                "  - Corrupted release file on GitHub",
                "\nTry downloading again or report the issue if it persists.",
            }
            error(table.concat(error_msg, "\n"))
        end
        print("Checksum verification passed")
    else
        print("WARNING: Proceeding without checksum verification (insecure)")
    end

    print(string.format("Extracting archive to: %s", install_path))
    local extract_err = archiver.decompress(temp_archive, install_path)
    if extract_err then
        os.remove(temp_archive)
        local error_msg = {
            "Failed to extract PostgreSQL archive.",
            string.format("\nArchive: %s", temp_archive),
            string.format("Destination: %s", install_path),
            string.format("Error: %s", tostring(extract_err)),
            "\nThe archive has been deleted.",
            "Possible causes:",
            "  - Corrupted archive file",
            "  - Insufficient disk space",
            "  - Permission issues in install directory",
        }
        error(table.concat(error_msg, "\n"))
    end

    local extracted_dir = string.format("%s/postgresql-%s-%s", install_path, version, platform)
    if not file.exists(extracted_dir) then
        local error_msg = {
            "Extraction succeeded but expected directory not found.",
            string.format("\nExpected: %s", extracted_dir),
            "This may indicate:",
            "  - Archive structure differs from expected format",
            "  - Extraction partially failed",
        }
        error(table.concat(error_msg, "\n"))
    end

    print(string.format("Moving files from extracted directory: %s", extracted_dir))
    if os_type == "windows" then
        local win_src = normalize_path(extracted_dir, os_type)
        local win_dest = normalize_path(install_path, os_type)
        local move_cmd = string.format(
            "powershell -NoProfile -Command \"Copy-Item -Path '%s\\*' -Destination '%s' -Recurse -Force; Remove-Item -Path '%s' -Recurse -Force\"",
            win_src,
            win_dest,
            win_src
        )
        local move_output = cmd.exec(move_cmd)
        if move_output and (move_output:match("[Ee]rror") or move_output:match("[Ff]ailed")) then
            local error_msg = {
                "Failed to move extracted files to install directory (Windows).",
                string.format("\nSource: %s", win_src),
                string.format("Destination: %s", win_dest),
                string.format("Command: %s", move_cmd),
                string.format("Error: %s", move_output),
            }
            error(table.concat(error_msg, "\n"))
        end
    else
        local move_cmd =
            string.format('sh -c \'cp -r "%s"/* "%s/" && rm -rf "%s"\'', extracted_dir, install_path, extracted_dir)
        local move_output = cmd.exec(move_cmd)
        if move_output and (move_output:match("[Ee]rror") or move_output:match("[Ff]ailed")) then
            local error_msg = {
                "Failed to move extracted files to install directory (Unix).",
                string.format("\nSource: %s", extracted_dir),
                string.format("Destination: %s", install_path),
                string.format("Command: %s", move_cmd),
                string.format("Error: %s", move_output),
            }
            error(table.concat(error_msg, "\n"))
        end
    end

    os.remove(temp_archive)
    print("PostgreSQL binary extraction and setup complete")
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

    print(string.format("Initializing PostgreSQL data directory at: %s", pgdata_dir))

    local initdb_bin = install_path .. "/bin/initdb"
    if os_type == "windows" then
        initdb_bin = initdb_bin .. ".exe"
    end

    if not file.exists(initdb_bin) then
        local error_msg = {
            "initdb binary not found. PostgreSQL installation may be incomplete.",
            string.format("\nExpected location: %s", initdb_bin),
            string.format("Install path: %s", install_path),
            "\nPossible causes:",
            "  - Extraction failed to create bin/ directory",
            "  - Incorrect platform binary downloaded",
            "  - Installation was interrupted",
            string.format("\nVerify that %s/bin directory exists and contains PostgreSQL binaries", install_path),
        }
        error(table.concat(error_msg, "\n"))
    end

    local initdb_path = os_type == "windows" and normalize_path(initdb_bin, os_type) or initdb_bin
    local pgdata_path = os_type == "windows" and normalize_path(pgdata_dir, os_type) or pgdata_dir
    local initdb_cmd = string.format('"%s" -D "%s" --encoding=UTF8 --locale=C', initdb_path, pgdata_path)

    print(string.format("Running: %s", initdb_cmd))
    local result = cmd.exec(initdb_cmd)

    if result:lower():match("error") or result:lower():match("failed") or result:lower():match("fatal") then
        local error_msg = {
            "initdb reported errors during database initialization.",
            string.format("\nCommand: %s", initdb_cmd),
            string.format("PGDATA: %s", pgdata_path),
            "\ninitdb output:",
            result,
            "\nPossible causes:",
            "  - Insufficient disk space",
            "  - Permission issues in install directory",
            "  - Unsupported locale settings",
            "  - Missing system libraries",
        }
        error(table.concat(error_msg, "\n"))
    end

    if not file.exists(pgdata_dir) then
        local error_msg = {
            "initdb completed but PGDATA directory was not created.",
            string.format("\nExpected: %s", pgdata_dir),
            string.format("Command: %s", initdb_cmd),
            "\ninitdb output:",
            result,
        }
        error(table.concat(error_msg, "\n"))
    end

    print("Database cluster initialized successfully")
    print(string.format("PGDATA location: %s", pgdata_dir))
end

--- Installs PostgreSQL from pre-built binaries with platform detection and SHA256 verification
--- @param ctx table Context containing tool, version, and install_path
--- @return table Empty table on success
function PLUGIN:BackendInstall(ctx)
    local tool = ctx.tool
    local version = ctx.version
    local install_path = ctx.install_path

    if not tool or tool == "" then
        error("Tool name is required but was not provided in context")
    end
    if not version or version == "" then
        error("Version is required but was not provided in context")
    end
    if not install_path or install_path == "" then
        error("Install path is required but was not provided in context")
    end

    if tool ~= "postgres" and tool ~= "postgresql" then
        local error_msg = {
            string.format("Unsupported tool: %s", tool),
            "\nThis backend only supports: 'postgres' or 'postgresql'",
            "Please check your mise configuration.",
        }
        error(table.concat(error_msg, "\n"))
    end

    print(string.format("=== PostgreSQL Installation ==="))
    print(string.format("Tool: %s", tool))
    print(string.format("Version: %s", version))
    print(string.format("Install path: %s", install_path))
    print(string.format("OS: %s", RUNTIME.osType))
    print(string.format("Architecture: %s", RUNTIME.archType))

    if not file.exists(install_path) then
        print(string.format("\nCreating install directory: %s", install_path))
        local os_type = RUNTIME.osType:lower()
        local mkdir_cmd
        if os_type == "windows" then
            mkdir_cmd = 'mkdir "' .. normalize_path(install_path, os_type) .. '"'
        else
            mkdir_cmd = 'mkdir -p "' .. install_path .. '"'
        end

        local mkdir_output = cmd.exec(mkdir_cmd)
        if mkdir_output and (mkdir_output:match("[Ee]rror") or mkdir_output:match("[Ff]ailed")) then
            local error_msg = {
                "Failed to create install directory.",
                string.format("\nPath: %s", install_path),
                string.format("Command: %s", mkdir_cmd),
                string.format("Error: %s", mkdir_output),
                "\nPossible causes:",
                "  - Permission denied",
                "  - Parent directory does not exist",
                "  - Disk is full or read-only",
            }
            error(table.concat(error_msg, "\n"))
        end

        if not file.exists(install_path) then
            error(
                string.format(
                    "mkdir command succeeded but directory not found: %s\nThis may indicate a filesystem issue.",
                    install_path
                )
            )
        end
    end

    local platform_target = get_rust_target()

    print(string.format("\nPlatform target: %s", platform_target))
    print("\n=== Downloading PostgreSQL ===")

    download_and_verify_postgresql(version, platform_target, install_path)

    print("\n=== Initializing Database Cluster ===")

    initialize_pgdata(install_path)

    print(string.format("\n=== Installation Complete ==="))
    print(string.format("PostgreSQL %s installed successfully", version))
    print(string.format("Location: %s", install_path))
    print(string.format("Binaries: %s/bin/", install_path))
    print(string.format("Data directory: %s/data/", install_path))
    return {}
end

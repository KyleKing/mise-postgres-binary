local cmd = require("cmd")
local file = require("file")
local http = require("http")
local archiver = require("archiver")
local lib = require("hooks.lib")

local function try_checksum_cmd(command, diagnostics, method, os_type)
    diagnostics[method].attempted = true
    diagnostics[method].command = command

    local output = cmd.exec(command)

    if output and output ~= "" then
        diagnostics[method].output = output
        local hash = lib.parse_sha256_from_output(output)
        if hash then
            diagnostics[method].success = true
            return hash
        end
        diagnostics[method].error = "Command succeeded but output did not contain valid SHA256 hash"
    else
        diagnostics[method].error = "Command returned empty output or command failed"
    end
    return nil
end

local function print_checksum_diagnostics(diagnostics)
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
end

local function checksum_error(filepath, diagnostics, troubleshooting)
    local skip_checksum = os.getenv("MISE_POSTGRES_BINARY_SKIP_CHECKSUM")
    if skip_checksum == "1" or skip_checksum == "true" then
        print(
            "WARNING: Skipping SHA256 verification (MISE_POSTGRES_BINARY_SKIP_CHECKSUM=1). This is insecure and not recommended."
        )
        print("\nDiagnostics for failed checksum attempts:")
        print(string.format("  File: %s", filepath))
        print_checksum_diagnostics(diagnostics)
        return nil
    end

    local error_msg = {
        "Failed to compute SHA256 checksum. All methods failed.",
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
    for _, tip in ipairs(troubleshooting) do
        table.insert(error_msg, "  - " .. tip)
    end
    error(table.concat(error_msg, "\n"))
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
        checksum = { attempted = false, success = false, error = nil, output = nil, command = nil },
    }

    local command
    if os_type == "windows" then
        local unix_filepath = filepath:gsub("\\", "/")
        command = string.format("sha256sum %s", unix_filepath)
    else
        command = string.format(
            '(sha256sum "%s" 2>/dev/null || shasum -a 256 "%s" 2>/dev/null) | awk \'{print $1}\'',
            filepath,
            filepath
        )
    end

    local hash = try_checksum_cmd(command, diagnostics, "checksum", os_type)
    if hash then
        return hash
    end

    if os_type == "windows" then
        print("WARNING: PowerShell checksum verification failed. Skipping SHA256 verification on Windows.")
        print("This may occur when running outside PowerShell (e.g., Git Bash, cmd.exe).")
        print("To enforce checksum verification, run mise from PowerShell.")
        print("\nDiagnostics:")
        print_checksum_diagnostics(diagnostics)
        return nil
    end

    local help_text = {
        "Ensure sha256sum (Linux) or shasum (macOS) is installed and in PATH",
        "To skip validation (insecure): export MISE_POSTGRES_BINARY_SKIP_CHECKSUM=1",
    }

    return checksum_error(filepath, diagnostics, help_text)
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

    local target = lib.get_rust_target(os_type, arch_type, is_musl)
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
    local os_type = RUNTIME.osType:lower()
    local base_url = string.format("https://github.com/theseus-rs/postgresql-binaries/releases/download/%s", version)

    local filename = string.format("postgresql-%s-%s.tar.gz", version, platform)
    local download_url = base_url .. "/" .. filename
    local checksum_url = download_url .. ".sha256"

    local path_sep = os_type == "windows" and "\\" or "/"
    local temp_archive = install_path .. path_sep .. filename

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

    local expected_sha256 = lib.parse_sha256_from_output(checksum_resp.body)
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

    local extracted_dir = install_path .. path_sep .. string.format("postgresql-%s-%s", version, platform)
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
        local move_succeeded = false
        local move_output = nil
        local move_cmd = nil

        local unix_test = cmd.exec("sh --version 2>&1 || echo NOTFOUND")
        local has_unix_shell = unix_test and not unix_test:match("NOTFOUND") and unix_test:match("sh")

        if has_unix_shell then
            local unix_src = lib.windows_to_unix_path(extracted_dir)
            local unix_dest = lib.windows_to_unix_path(install_path)
            move_cmd = string.format("cp -r %s/. %s/", unix_src, unix_dest)
            move_output = cmd.exec(move_cmd)
            local bin_check = install_path .. "\\bin"
            if file.exists(bin_check) then
                local rm_cmd = string.format("rm -rf %s", unix_src)
                cmd.exec(rm_cmd)
                move_succeeded = true
            end
        end

        if not move_succeeded then
            if has_unix_shell then
                print("Falling back to native Windows commands")
            end
            local win_src = lib.normalize_path(extracted_dir, os_type)
            local win_dest = lib.normalize_path(install_path, os_type)

            move_cmd = string.format("xcopy %s %s /E /Y /I /Q", win_src, win_dest)
            move_output = cmd.exec(move_cmd)

            local bin_check = install_path .. "\\bin"
            if file.exists(bin_check) then
                local rmdir_cmd = string.format("rmdir /S /Q %s", win_src)
                cmd.exec(rmdir_cmd)
                move_succeeded = true
            end
        end

        if not move_succeeded then
            local error_msg = {
                "Failed to move extracted files to install directory (Windows).",
                string.format("\nExtracted directory: %s", extracted_dir),
                string.format("Install path: %s", install_path),
                string.format("Last command: %s", move_cmd),
                string.format("Error: %s", move_output or "(empty output)"),
            }
            error(table.concat(error_msg, "\n"))
        end

        local bin_dir = install_path .. "\\bin"
        if not file.exists(bin_dir) then
            local error_msg = {
                "File move completed but bin directory not found.",
                string.format("\nExpected bin directory: %s", bin_dir),
                string.format("Install path: %s", install_path),
                string.format("Install directory exists: %s", tostring(file.exists(install_path))),
                string.format("Extracted directory existed: %s", tostring(file.exists(extracted_dir))),
                string.format("Move command used: %s", move_cmd),
                string.format("Command output: %s", move_output or "(empty)"),
                "\nPossible causes:",
                "  - Archive extraction created unexpected directory structure",
                "  - File move succeeded but bin directory wasn't in the extracted files",
                "  - PowerShell Copy-Item failed silently in non-PowerShell environment",
                "\nTo debug, check the contents of the install directory manually.",
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
    local path_sep = os_type == "windows" and "\\" or "/"

    local pgdata_dir = install_path .. path_sep .. "data"

    if file.exists(pgdata_dir) then
        print("PGDATA directory already exists, skipping initdb")
        return
    end

    print(string.format("Initializing PostgreSQL data directory at: %s", pgdata_dir))

    local initdb_bin = install_path .. path_sep .. "bin" .. path_sep .. "initdb"
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

    local initdb_path = os_type == "windows" and initdb_bin:gsub("\\", "/") or initdb_bin
    local pgdata_path = os_type == "windows" and pgdata_dir:gsub("\\", "/") or pgdata_dir
    local initdb_cmd = string.format("%s -D %s --encoding=UTF8 --locale=C", initdb_path, pgdata_path)

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
            mkdir_cmd = "mkdir " .. install_path:gsub("\\", "/")
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

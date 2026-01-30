local M = {}

function M.trim(str)
    if not str then
        return nil
    end
    return str:match("^%s*(.-)%s*$")
end

function M.is_valid_sha256(str)
    if not str then
        return false
    end
    local trimmed = M.trim(str)
    return trimmed:match("^%x+$") ~= nil and #trimmed == 64
end

--- Find the first 64-character hex sequence in output, returned lowercase.
--- Handles plain hash, sha256sum/awk output with trailing newline, and
--- CertUtil multi-line output.
function M.parse_sha256_from_output(output)
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

function M.parse_major_version(version)
    if not version then
        return nil
    end
    local major = version:match("^(%d+)%.")
    return major and tonumber(major) or nil
end

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

--- Map OS, architecture, and optional musl flag to a Rust target triple.
--- @param os_type string Lowercase OS name (darwin, linux, windows)
--- @param arch_type string Architecture (amd64, arm64, 386)
--- @param is_musl boolean|nil Whether the system uses musl libc
--- @return string|nil Rust target triple or nil if unsupported
function M.get_rust_target(os_type, arch_type, is_musl)
    if os_type == "linux" then
        local suffix = is_musl and "musl" or "gnu"
        return RUST_TARGETS[os_type .. "-" .. arch_type .. "-" .. suffix]
    end
    return RUST_TARGETS[os_type .. "-" .. arch_type]
end

function M.normalize_path(path, os_type)
    if not path then
        return nil
    end
    if os_type == "windows" then
        return path:gsub("/", "\\")
    end
    return path
end

return M

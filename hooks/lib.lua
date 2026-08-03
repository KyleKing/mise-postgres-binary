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

local function version_parts(version)
    local parts = {}
    for number in tostring(version):gmatch("%d+") do
        table.insert(parts, tonumber(number))
    end
    return parts
end

--- Orders versions ascending so that mise resolves a prefix query to the newest match
--- @param versions string[] Semver-like version strings
--- @return string[] New sorted array; the input is left untouched
function M.sort_versions(versions)
    local sorted = {}
    for index, version in ipairs(versions) do
        sorted[index] = version
    end

    table.sort(sorted, function(left, right)
        local left_parts = version_parts(left)
        local right_parts = version_parts(right)
        for index = 1, math.max(#left_parts, #right_parts) do
            local left_part = left_parts[index] or 0
            local right_part = right_parts[index] or 0
            if left_part ~= right_part then
                return left_part < right_part
            end
        end
        return left < right
    end)

    return sorted
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

function M.windows_to_unix_path(path)
    if not path then
        return nil
    end
    local unix_path = path:gsub("\\", "/")
    unix_path = unix_path:gsub("^(%a):/", function(drive)
        return "/" .. drive:lower() .. "/"
    end)
    return unix_path
end

return M

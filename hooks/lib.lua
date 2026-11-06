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

function M.get_github_token()
    local token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
    if token and token ~= "" then
        return token
    end
    return nil
end

--- @param release table Decoded GitHub release object
--- @param asset_name string Exact asset file name
--- @return string|nil Release-asset API URL, or nil when the release has no such asset
function M.find_asset_api_url(release, asset_name)
    for _, asset in ipairs(type(release) == "table" and release.assets or {}) do
        if asset.name == asset_name then
            return asset.url
        end
    end
    return nil
end

local EXTENSIONS = {
    pgvector = {
        control = "vector",
        repo = "https://github.com/pgvector/pgvector.git",
        commits = { ["0.8.2"] = "cab9da72c04353f143bb06b42ab70a403daac64a" },
    },
}

--- @param option string|string[]|nil Value of the `extensions` tool option
--- @return string[] Extension specs such as "pgvector@0.8.2"
function M.normalize_extensions(option)
    local specs = {}
    if type(option) == "string" then
        for spec in option:gmatch("[^,%s]+") do
            table.insert(specs, spec)
        end
    elseif type(option) == "table" then
        for _, spec in ipairs(option) do
            table.insert(specs, spec)
        end
    end
    return specs
end

--- @param spec string Extension spec such as "pgvector@0.8.2"
--- @return table|nil Extension name, version, repo, and pinned commit
--- @return string|nil Error message when the spec is not a pinned, supported extension
function M.resolve_extension(spec)
    local name, version = tostring(spec):match("^([%w_-]+)@([%w.]+)$")
    if not name then
        return nil, string.format("Invalid extension %q, expected name@version (e.g. pgvector@0.8.2)", tostring(spec))
    end
    local extension = EXTENSIONS[name]
    if not extension then
        return nil, string.format("Unsupported extension %q", name)
    end
    local commit = extension.commits[version]
    if not commit then
        local known = {}
        for known_version in pairs(extension.commits) do
            table.insert(known, known_version)
        end
        table.sort(known)
        return nil, string.format("Unsupported %s version %s (supported: %s)", name, version, table.concat(known, ", "))
    end
    return { name = name, version = version, repo = extension.repo, commit = commit, control = extension.control }
end

--- @param extension table Result of resolve_extension
--- @param install_path string PostgreSQL installation directory
--- @return string POSIX shell script that builds the extension into install_path and fails on a commit mismatch
function M.build_extension_script(extension, install_path)
    return table.concat({
        "set -eu",
        'work="$(mktemp -d)"',
        "trap 'rm -rf \"$work\"' EXIT",
        string.format('git clone --quiet --depth 1 --branch "v%s" "%s" "$work/src"', extension.version, extension.repo),
        'actual="$(git -C "$work/src" rev-parse HEAD)"',
        string.format(
            'if [ "$actual" != "%s" ]; then echo "%s v%s resolved to $actual, expected %s" >&2; exit 1; fi',
            extension.commit,
            extension.name,
            extension.version,
            extension.commit
        ),
        'if [ "$(uname -s)" = Darwin ]; then',
        '  sdk="$(xcrun --show-sdk-path)"',
        '  set -- "OPTFLAGS=" "CPPFLAGS=-isysroot $sdk" "LDFLAGS=-isysroot $sdk"',
        "else",
        '  set -- "OPTFLAGS="',
        "fi",
        string.format('pg_config="%s/bin/pg_config"', install_path),
        'make -C "$work/src" PG_CONFIG="$pg_config" "$@"',
        'make -C "$work/src" PG_CONFIG="$pg_config" "$@" install',
        string.format('test -f "$("$pg_config" --sharedir)/extension/%s.control"', extension.control),
    }, "\n")
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

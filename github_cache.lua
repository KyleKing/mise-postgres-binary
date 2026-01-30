local M = {}

local DEFAULT_TTL = 43200

local function _get_json()
    local ok, mod = pcall(require, "json")
    if ok then
        return mod
    end
    ok, mod = pcall(require, "dkjson")
    if ok then
        return mod
    end
    return nil
end

local _json = _get_json()

local function _get_home()
    return os.getenv("HOME") or os.getenv("USERPROFILE") or ""
end

function M.get_cache_dir()
    local xdg = os.getenv("XDG_CACHE_HOME")
    if xdg and xdg ~= "" then
        return xdg .. "/mise/postgres-binary"
    end

    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        local localappdata = os.getenv("LOCALAPPDATA")
        if localappdata and localappdata ~= "" then
            return localappdata .. "\\mise\\postgres-binary"
        end
        return _get_home() .. "\\.cache\\mise\\postgres-binary"
    end

    local uname_ok, uname_result = pcall(function()
        local handle = io.popen("uname -s 2>/dev/null")
        if handle then
            local result = handle:read("*a")
            handle:close()
            return result or ""
        end
        return ""
    end)

    if uname_ok and uname_result and uname_result:match("Darwin") then
        return _get_home() .. "/Library/Caches/mise/postgres-binary"
    end

    return _get_home() .. "/.cache/mise/postgres-binary"
end

function M.ensure_cache_dir()
    local dir = M.get_cache_dir()
    local sep = package.config:sub(1, 1)
    if sep == "\\" then
        os.execute('mkdir "' .. dir .. '" 2>nul')
    else
        os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
    end
end

local function _cache_file_path()
    return M.get_cache_dir() .. "/" .. "github_releases.json"
end

function M.get_cache()
    if not _json then
        return nil
    end

    local path = _cache_file_path()
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()

    if not content or content == "" then
        return nil
    end

    local ok, data = pcall(_json.decode, content)
    if not ok or type(data) ~= "table" then
        return nil
    end

    if not data.timestamp or not data.versions then
        return nil
    end

    return data
end

function M.set_cache(versions, etag, last_modified)
    if not _json then
        return
    end

    M.ensure_cache_dir()

    local data = {
        timestamp = os.time(),
        etag = etag,
        last_modified = last_modified,
        versions = versions,
    }

    local path = _cache_file_path()
    local file = io.open(path, "w")
    if not file then
        return
    end

    local ok, encoded = pcall(_json.encode, data)
    if ok and encoded then
        file:write(encoded)
    end
    file:close()
end

function M.is_cache_valid(cache_data)
    if not cache_data or not cache_data.timestamp then
        return false
    end

    local ttl_str = os.getenv("MISE_POSTGRES_BINARY_CACHE_TTL")
    local ttl = DEFAULT_TTL
    if ttl_str and ttl_str ~= "" then
        local parsed = tonumber(ttl_str)
        if parsed then
            ttl = parsed
        end
    end

    if ttl <= 0 then
        return false
    end

    return os.time() - cache_data.timestamp < ttl
end

function M.touch_cache(cache_data)
    if not _json or not cache_data then
        return
    end

    cache_data.timestamp = os.time()

    local path = _cache_file_path()
    local file = io.open(path, "w")
    if not file then
        return
    end

    local ok, encoded = pcall(_json.encode, cache_data)
    if ok and encoded then
        file:write(encoded)
    end
    file:close()
end

return M

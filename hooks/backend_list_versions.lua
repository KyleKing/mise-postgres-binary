local http = require("http")
local json = require("json")

local source = debug.getinfo(1, "S").source:sub(2)
local hook_dir = source:match("(.*[/\\])") or ""
local lib = dofile(hook_dir .. "../lib.lua")

local MIN_MAJOR_VERSION = 13
local RELEASES_PER_PAGE = 100
local MAX_PAGES = 2

--- Fetch releases from a single GitHub API page
--- @param page number Page number to fetch
--- @return table Array of release objects
local function fetch_page(page)
    local api_url = string.format(
        "https://api.github.com/repos/theseus-rs/postgresql-binaries/releases?per_page=%d&page=%d",
        RELEASES_PER_PAGE,
        page
    )

    local request_opts = { url = api_url }
    local github_token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
    if github_token and github_token ~= "" then
        request_opts.headers = {
            ["Authorization"] = "Bearer " .. github_token,
        }
    end

    local resp, err = http.get(request_opts)
    if err then
        error("Failed to fetch versions from GitHub API (page " .. page .. "): " .. tostring(err))
    end

    if resp.status_code and resp.status_code ~= 200 then
        local err_msg = string.format(
            "GitHub API returned status %d (page %d). This may indicate rate limiting or API issues. Response: %s",
            resp.status_code,
            page,
            resp.body or "no body"
        )
        if resp.status_code == 403 and (resp.body or ""):match("rate limit") then
            err_msg = err_msg
                .. "\n\nTip: Set GITHUB_TOKEN environment variable to increase rate limit from 60 to 5000 requests/hour."
        end
        error(err_msg)
    end

    if not resp.body or resp.body == "" then
        error("GitHub API returned empty response body (page " .. page .. ")")
    end

    local ok, decoded = pcall(json.decode, resp.body)
    if not ok then
        error("Failed to parse JSON from GitHub API (page " .. page .. "): " .. tostring(decoded))
    end

    if type(decoded) ~= "table" then
        error("GitHub API returned unexpected format (page " .. page .. "): expected array, got " .. type(decoded))
    end

    return decoded
end

--- Lists available PostgreSQL versions from theseus-rs/postgresql-binaries GitHub releases
---
--- Performance notes:
--- - Fetches up to MAX_PAGES pages (200 versions by default)
--- - mise caches this list, so this function is only called when cache expires or user runs `mise ls-remote`
--- - Filtering by MIN_MAJOR_VERSION reduces noise from EOL PostgreSQL versions
--- - GitHub API rate limit: 60 req/hour (unauthenticated), 5000/hour (authenticated)
---
--- @param ctx table Context containing tool information
--- @return table Table with versions array
function PLUGIN:BackendListVersions(ctx)
    local tool = ctx.tool

    if tool ~= "postgres" and tool ~= "postgresql" then
        return { versions = {} }
    end

    local all_versions = {}
    local oldest_major_seen = 999

    for page = 1, MAX_PAGES do
        local releases = fetch_page(page)

        if #releases == 0 then
            break
        end

        for _, release in ipairs(releases) do
            local version = release.tag_name
            if version then
                local major = lib.parse_major_version(version)

                if major and major < oldest_major_seen then
                    oldest_major_seen = major
                end

                if major and major >= MIN_MAJOR_VERSION then
                    table.insert(all_versions, version)
                end
            end
        end

        if oldest_major_seen < MIN_MAJOR_VERSION then
            break
        end
    end

    if #all_versions == 0 then
        error("No supported versions found in theseus-rs/postgresql-binaries releases")
    end

    return { versions = all_versions }
end

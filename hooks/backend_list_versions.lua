local http = require("http")
local json = require("json")

-- Configuration constants
local MIN_MAJOR_VERSION = 13 -- PostgreSQL 13+ are actively supported
local RELEASES_PER_PAGE = 100 -- GitHub API max per page
local MAX_PAGES = 2 -- Fetch up to 200 releases (covers all supported versions)

--- Parse major version from semver string (e.g., "15.10.0" -> 15)
--- @param version string Version string
--- @return number|nil Major version number or nil if unparseable
local function parse_major_version(version)
    local major = version:match("^(%d+)%.")
    return major and tonumber(major) or nil
end

--- Fetch releases from a single GitHub API page
--- @param page number Page number to fetch
--- @return table Array of release objects
local function fetch_page(page)
    local api_url = string.format(
        "https://api.github.com/repos/theseus-rs/postgresql-binaries/releases?per_page=%d&page=%d",
        RELEASES_PER_PAGE,
        page
    )

    local resp, err = http.get({ url = api_url })
    if err then
        error("Failed to fetch versions from GitHub API (page " .. page .. "): " .. tostring(err))
    end

    return json.decode(resp.body)
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

    -- Only handle postgres/postgresql tools
    if tool ~= "postgres" and tool ~= "postgresql" then
        return { versions = {} }
    end

    local all_versions = {}
    local oldest_major_seen = 999

    -- Fetch multiple pages to get comprehensive version coverage
    -- GitHub returns releases in reverse chronological order (newest first)
    for page = 1, MAX_PAGES do
        local releases = fetch_page(page)

        -- Empty page means we've reached the end
        if #releases == 0 then
            break
        end

        for _, release in ipairs(releases) do
            local version = release.tag_name
            if version then
                local major = parse_major_version(version)

                -- Track oldest major version seen to know when to stop
                if major and major < oldest_major_seen then
                    oldest_major_seen = major
                end

                -- Only include supported major versions
                if major and major >= MIN_MAJOR_VERSION then
                    table.insert(all_versions, version)
                end
            end
        end

        -- Early exit: if we've already seen versions older than supported range,
        -- no need to fetch more pages
        if oldest_major_seen < MIN_MAJOR_VERSION then
            break
        end
    end

    if #all_versions == 0 then
        error("No supported versions found in theseus-rs/postgresql-binaries releases")
    end

    return { versions = all_versions }
end

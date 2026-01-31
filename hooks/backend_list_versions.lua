local http = require("http")
local json = require("json")
local github_cache = require("hooks.github_cache")

local function parse_major_version(version)
    if not version then
        return nil
    end
    local major = version:match("^(%d+)%.")
    return major and tonumber(major) or nil
end

local MIN_MAJOR_VERSION = 13
local RELEASES_PER_PAGE = 100
local MAX_PAGES = 2
local REQUEST_TIMEOUT_MS = 30000

--- @param page number Page number to fetch
--- @param conditional_headers table|nil Optional {etag, last_modified} for conditional requests
--- @return table|nil Array of release objects (nil on 304)
--- @return table|nil Response headers {etag, last_modified} (nil on 304)
local function fetch_page(page, conditional_headers)
    local api_url = string.format(
        "https://api.github.com/repos/theseus-rs/postgresql-binaries/releases?per_page=%d&page=%d",
        RELEASES_PER_PAGE,
        page
    )

    local headers = {}
    local github_token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")
    if github_token and github_token ~= "" then
        headers["Authorization"] = "Bearer " .. github_token
    end

    if conditional_headers then
        if conditional_headers.etag then
            headers["If-None-Match"] = conditional_headers.etag
        end
        if conditional_headers.last_modified then
            headers["If-Modified-Since"] = conditional_headers.last_modified
        end
    end

    local request_opts = {
        url = api_url,
        timeout = REQUEST_TIMEOUT_MS,
    }
    if next(headers) then
        request_opts.headers = headers
    end

    local resp, err = http.get(request_opts)
    if err then
        local err_str = tostring(err)
        if err_str:match("timeout") or err_str:match("deadline") then
            error(
                string.format(
                    "GitHub API request timed out after %dms (page %d). Check network connectivity.",
                    REQUEST_TIMEOUT_MS,
                    page
                )
            )
        end
        error("Failed to fetch versions from GitHub API (page " .. page .. "): " .. err_str)
    end

    if resp.status_code == 304 then
        return nil, nil
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

    local resp_headers = nil
    if resp.headers then
        resp_headers = {
            etag = resp.headers["etag"],
            last_modified = resp.headers["last-modified"],
        }
    end

    return decoded, resp_headers
end

local function extract_versions(releases_pages)
    local all_versions = {}
    local oldest_major_seen = 999

    for _, releases in ipairs(releases_pages) do
        for _, release in ipairs(releases) do
            local version = release.tag_name
            if version then
                local major = parse_major_version(version)

                if major and major < oldest_major_seen then
                    oldest_major_seen = major
                end

                if major and major >= MIN_MAJOR_VERSION then
                    table.insert(all_versions, version)
                end
            end
        end
    end

    return all_versions, oldest_major_seen
end

local function fetch_all_pages()
    local pages = {}
    local last_resp_headers = nil

    for page = 1, MAX_PAGES do
        local releases, resp_headers = fetch_page(page)
        if not releases or #releases == 0 then
            break
        end

        if page == 1 then
            last_resp_headers = resp_headers
        end
        table.insert(pages, releases)

        local _, oldest = extract_versions({ releases })
        if oldest < MIN_MAJOR_VERSION then
            break
        end
    end

    return pages, last_resp_headers
end

--- @param ctx table Context containing tool information
--- @return table Table with versions array
function PLUGIN:BackendListVersions(ctx)
    local tool = ctx.tool

    if tool ~= "postgres" and tool ~= "postgresql" then
        return { versions = {} }
    end

    local cache_data = github_cache.get_cache()

    if cache_data and github_cache.is_cache_valid(cache_data) then
        return { versions = cache_data.versions }
    end

    if cache_data and (cache_data.etag or cache_data.last_modified) then
        local releases, _ = fetch_page(1, {
            etag = cache_data.etag,
            last_modified = cache_data.last_modified,
        })

        if not releases then
            github_cache.touch_cache(cache_data)
            return { versions = cache_data.versions }
        end
    end

    local pages, resp_headers = fetch_all_pages()
    local all_versions = extract_versions(pages)

    if #all_versions == 0 then
        error("No supported versions found in theseus-rs/postgresql-binaries releases")
    end

    local etag = resp_headers and resp_headers.etag or nil
    local last_modified = resp_headers and resp_headers.last_modified or nil
    github_cache.set_cache(all_versions, etag, last_modified)

    return { versions = all_versions }
end

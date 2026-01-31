local github_cache = require("src.github_cache")

local function _temp_dir()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute('mkdir -p "' .. dir .. '"')
    return dir
end

local function _cleanup(dir)
    os.execute('rm -rf "' .. dir .. '"')
end

describe("github_cache", function()
    describe("get_cache_dir", function()
        local orig_getenv = os.getenv

        after_each(function()
            os.getenv = orig_getenv
        end)

        it("uses XDG_CACHE_HOME when set", function()
            os.getenv = function(name)
                if name == "XDG_CACHE_HOME" then
                    return "/custom/cache"
                end
                return orig_getenv(name)
            end
            assert.are.equal("/custom/cache/mise/postgres-binary", github_cache.get_cache_dir())
        end)

        it("returns a non-empty path with default env", function()
            local dir = github_cache.get_cache_dir()
            assert.is_not_nil(dir)
            assert.is_true(#dir > 0)
            assert.truthy(dir:match("mise/postgres%-binary$") or dir:match("mise\\postgres%-binary$"))
        end)
    end)

    describe("is_cache_valid", function()
        local orig_getenv = os.getenv

        after_each(function()
            os.getenv = orig_getenv
        end)

        it("returns false for nil cache_data", function()
            assert.is_false(github_cache.is_cache_valid(nil))
        end)

        it("returns false for missing timestamp", function()
            assert.is_false(github_cache.is_cache_valid({ versions = {} }))
        end)

        it("returns true for fresh cache", function()
            local data = { timestamp = os.time(), versions = { "18.1.0" } }
            assert.is_true(github_cache.is_cache_valid(data))
        end)

        it("returns false for stale cache", function()
            local data = { timestamp = os.time() - 99999, versions = { "18.1.0" } }
            assert.is_false(github_cache.is_cache_valid(data))
        end)

        it("respects MISE_POSTGRES_BINARY_CACHE_TTL override", function()
            os.getenv = function(name)
                if name == "MISE_POSTGRES_BINARY_CACHE_TTL" then
                    return "1"
                end
                return orig_getenv(name)
            end
            local data = { timestamp = os.time() - 2, versions = { "18.1.0" } }
            assert.is_false(github_cache.is_cache_valid(data))
        end)

        it("returns false when TTL is zero", function()
            os.getenv = function(name)
                if name == "MISE_POSTGRES_BINARY_CACHE_TTL" then
                    return "0"
                end
                return orig_getenv(name)
            end
            local data = { timestamp = os.time(), versions = { "18.1.0" } }
            assert.is_false(github_cache.is_cache_valid(data))
        end)
    end)

    describe("get_cache", function()
        local orig_get_cache_dir
        local tmp

        before_each(function()
            tmp = _temp_dir()
            orig_get_cache_dir = github_cache.get_cache_dir
            github_cache.get_cache_dir = function()
                return tmp
            end
        end)

        after_each(function()
            github_cache.get_cache_dir = orig_get_cache_dir
            _cleanup(tmp)
        end)

        it("returns nil when no cache file exists", function()
            assert.is_nil(github_cache.get_cache())
        end)

        it("returns nil for malformed JSON", function()
            local file = io.open(tmp .. "/github_releases.json", "w")
            file:write("not json")
            file:close()
            assert.is_nil(github_cache.get_cache())
        end)

        it("returns nil for JSON missing required fields", function()
            local file = io.open(tmp .. "/github_releases.json", "w")
            file:write('{"foo": "bar"}')
            file:close()
            assert.is_nil(github_cache.get_cache())
        end)

        it("returns valid cache data", function()
            local json = require("dkjson")
            local data = {
                timestamp = 1000000,
                etag = '"abc123"',
                last_modified = "Thu, 01 Jan 2026 00:00:00 GMT",
                versions = { "18.1.0", "17.4.0" },
            }
            local file = io.open(tmp .. "/github_releases.json", "w")
            file:write(json.encode(data))
            file:close()

            local result = github_cache.get_cache()
            assert.is_not_nil(result)
            assert.are.equal(1000000, result.timestamp)
            assert.are.equal('"abc123"', result.etag)
            assert.are.same({ "18.1.0", "17.4.0" }, result.versions)
        end)
    end)

    describe("set_cache", function()
        local orig_get_cache_dir
        local tmp

        before_each(function()
            tmp = _temp_dir()
            orig_get_cache_dir = github_cache.get_cache_dir
            github_cache.get_cache_dir = function()
                return tmp
            end
        end)

        after_each(function()
            github_cache.get_cache_dir = orig_get_cache_dir
            _cleanup(tmp)
        end)

        it("writes cache file that can be read back", function()
            github_cache.set_cache({ "18.1.0", "17.4.0" }, '"etag-val"', "Thu, 01 Jan 2026 00:00:00 GMT")

            local result = github_cache.get_cache()
            assert.is_not_nil(result)
            assert.are.same({ "18.1.0", "17.4.0" }, result.versions)
            assert.are.equal('"etag-val"', result.etag)
            assert.is_true(result.timestamp > 0)
        end)

        it("handles nil etag and last_modified", function()
            github_cache.set_cache({ "18.1.0" }, nil, nil)

            local result = github_cache.get_cache()
            assert.is_not_nil(result)
            assert.are.same({ "18.1.0" }, result.versions)
        end)
    end)

    describe("touch_cache", function()
        local orig_get_cache_dir
        local tmp

        before_each(function()
            tmp = _temp_dir()
            orig_get_cache_dir = github_cache.get_cache_dir
            github_cache.get_cache_dir = function()
                return tmp
            end
        end)

        after_each(function()
            github_cache.get_cache_dir = orig_get_cache_dir
            _cleanup(tmp)
        end)

        it("updates timestamp without changing versions", function()
            github_cache.set_cache({ "18.1.0" }, '"etag"', "modified-date")

            local before = github_cache.get_cache()
            local old_ts = before.timestamp

            os.execute("sleep 1")
            github_cache.touch_cache(before)

            local after = github_cache.get_cache()
            assert.are.same({ "18.1.0" }, after.versions)
            assert.are.equal('"etag"', after.etag)
            assert.is_true(after.timestamp >= old_ts)
        end)
    end)
end)

describe("backend_list_versions", function()
    local backend_list_versions
    local PLUGIN
    local mock_http
    local mock_json
    local github_cache
    local orig_require

    before_each(function()
        _G.PLUGIN = {}
        github_cache = require("hooks.github_cache")

        mock_http = {
            get = function()
                return {
                    status_code = 200,
                    body = "[]",
                    headers = {},
                },
                    nil
            end,
        }

        mock_json = {
            decode = function(str)
                return require("dkjson").decode(str)
            end,
        }

        orig_require = require
        _G.require = function(name)
            if name == "http" then
                return mock_http
            elseif name == "json" then
                return mock_json
            end
            return orig_require(name)
        end

        local chunk = assert(loadfile("hooks/backend_list_versions.lua"))
        chunk()
        PLUGIN = _G.PLUGIN
        backend_list_versions = PLUGIN.BackendListVersions
    end)

    after_each(function()
        _G.PLUGIN = nil
        _G.require = orig_require
    end)

    describe("PLUGIN:BackendListVersions", function()
        it("should return empty versions for non-postgres tools", function()
            local ctx = {
                tool = "mysql",
            }

            local result = backend_list_versions(PLUGIN, ctx)

            assert.is_not_nil(result)
            assert.is_table(result.versions)
            assert.are.equal(0, #result.versions)
        end)

        it("should handle postgresql tool name", function()
            local ctx = {
                tool = "postgresql",
            }

            local orig_get_cache = github_cache.get_cache
            local orig_set_cache = github_cache.set_cache
            local call_count = 0

            mock_http.get = function()
                call_count = call_count + 1
                if call_count == 1 then
                    return {
                        status_code = 200,
                        body = '[{"tag_name": "14.0.0"}]',
                        headers = {},
                    },
                        nil
                else
                    return {
                        status_code = 200,
                        body = "[]",
                        headers = {},
                    },
                        nil
                end
            end

            github_cache.get_cache = function()
                return nil
            end

            github_cache.set_cache = function() end

            local result = backend_list_versions(PLUGIN, ctx)

            github_cache.get_cache = orig_get_cache
            github_cache.set_cache = orig_set_cache

            assert.is_not_nil(result)
            assert.is_table(result.versions)
            assert.are.equal(1, #result.versions)
            assert.are.equal("14.0.0", result.versions[1])
        end)

        describe("version filtering", function()
            local orig_get_cache
            local orig_set_cache

            before_each(function()
                orig_get_cache = github_cache.get_cache
                orig_set_cache = github_cache.set_cache

                github_cache.get_cache = function()
                    return nil
                end
                github_cache.set_cache = function() end
            end)

            after_each(function()
                github_cache.get_cache = orig_get_cache
                github_cache.set_cache = orig_set_cache
            end)

            it("should filter by minimum major version (>= 13)", function()
                mock_http.get = function()
                    return {
                        status_code = 200,
                        body = '[{"tag_name": "15.1.0"}, {"tag_name": "14.2.0"}, {"tag_name": "13.0.0"}, {"tag_name": "12.9.0"}, {"tag_name": "11.18.0"}]',
                        headers = {},
                    },
                        nil
                end

                local ctx = { tool = "postgres" }
                local result = backend_list_versions(PLUGIN, ctx)

                assert.is_not_nil(result)
                assert.is_table(result.versions)
                assert.are.equal(3, #result.versions)

                local has_15 = false
                local has_14 = false
                local has_13 = false
                local has_12 = false
                for _, v in ipairs(result.versions) do
                    if v == "15.1.0" then
                        has_15 = true
                    end
                    if v == "14.2.0" then
                        has_14 = true
                    end
                    if v == "13.0.0" then
                        has_13 = true
                    end
                    if v == "12.9.0" then
                        has_12 = true
                    end
                end

                assert.is_true(has_15, "Should include version 15.1.0")
                assert.is_true(has_14, "Should include version 14.2.0")
                assert.is_true(has_13, "Should include version 13.0.0")
                assert.is_false(has_12, "Should exclude version 12.9.0")
            end)

            it("should handle empty releases", function()
                mock_http.get = function()
                    return {
                        status_code = 200,
                        body = "[]",
                        headers = {},
                    },
                        nil
                end

                local ctx = { tool = "postgres" }

                local ok, err = pcall(function()
                    backend_list_versions(PLUGIN, ctx)
                end)

                assert.is_false(ok)
                assert.truthy(tostring(err):match("No supported versions"))
            end)

            it("should use cached versions when valid", function()
                local cache_called = false
                github_cache.get_cache = function()
                    cache_called = true
                    return {
                        timestamp = os.time(),
                        versions = { "15.1.0", "14.2.0" },
                    }
                end

                github_cache.is_cache_valid = function()
                    return true
                end

                local ctx = { tool = "postgres" }
                local result = backend_list_versions(PLUGIN, ctx)

                assert.is_true(cache_called)
                assert.are.equal(2, #result.versions)
                assert.are.equal("15.1.0", result.versions[1])
                assert.are.equal("14.2.0", result.versions[2])
            end)
        end)
    end)
end)

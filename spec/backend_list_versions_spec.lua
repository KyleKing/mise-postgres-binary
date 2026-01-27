-- Tests for hooks/backend_list_versions.lua
--
-- Note: These hooks run within mise's Lua environment which provides special
-- modules (http, json) that aren't available in standard Lua. Full integration
-- testing is done via CI and test-integration task.

describe("backend_list_versions", function()
    it("should exist and be syntactically valid", function()
        local f, err = loadfile("hooks/backend_list_versions.lua")
        assert.is_not_nil(f, "Failed to load backend_list_versions.lua: " .. tostring(err))
    end)

    describe("parse_major_version", function()
        -- Note: parse_major_version is a local function within mise's environment
        -- and can't be tested directly without mocking mise modules
        pending("would parse major version from semver string in mise environment")
    end)

    describe("PLUGIN:BackendListVersions", function()
        pending("integration test: should return empty versions for non-postgres tools")
        pending("integration test: should fetch versions from GitHub API")
        pending("integration test: should filter by minimum major version")
    end)
end)

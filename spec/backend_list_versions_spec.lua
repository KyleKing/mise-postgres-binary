local lib = require("src.lib")

describe("backend_list_versions", function()
    it("should exist and be syntactically valid", function()
        local f, err = loadfile("hooks/backend_list_versions.lua")
        assert.is_not_nil(f, "Failed to load backend_list_versions.lua: " .. tostring(err))
    end)

    describe("parse_major_version (via lib)", function()
        it("parses major version from semver string", function()
            assert.are.equal(15, lib.parse_major_version("15.10.0"))
        end)

        it("returns nil for non-version string", function()
            assert.is_nil(lib.parse_major_version("latest"))
        end)
    end)

    describe("PLUGIN:BackendListVersions", function()
        pending("integration test: should return empty versions for non-postgres tools")
        pending("integration test: should fetch versions from GitHub API")
        pending("integration test: should filter by minimum major version")
    end)
end)

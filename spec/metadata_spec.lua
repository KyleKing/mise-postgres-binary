-- Tests for metadata.lua
describe("metadata", function()
    it("should be syntactically valid Lua", function()
        local f, err = loadfile("metadata.lua")
        assert.is_not_nil(f, "Failed to load metadata.lua: " .. tostring(err))
    end)

    it("should contain valid metadata structure", function()
        local content = io.open("metadata.lua", "r"):read("*all")

        -- Check for required fields in the source (uses PLUGIN global)
        assert.is_truthy(content:match("PLUGIN%s*=%s*{"), "Should define PLUGIN table")
        assert.is_truthy(content:match("name%s*=%s*[\"']"), "Should have name field")
        assert.is_truthy(content:match("version%s*=%s*[\"']"), "Should have version field")
        assert.is_truthy(content:match("description%s*=%s*[\"']"), "Should have description field")
        assert.is_truthy(content:match("author%s*=%s*[\"']"), "Should have author field")
    end)

    it("should have valid semantic version", function()
        local content = io.open("metadata.lua", "r"):read("*all")
        local version = content:match("version%s*=%s*[\"']([^\"']+)[\"']")

        assert.is_not_nil(version, "Should extract version string")
        -- Check basic semver format (X.Y.Z)
        assert.is_truthy(
            version:match("^%d+%.%d+%.%d+$"),
            string.format("Version '%s' should match semver pattern X.Y.Z", version)
        )
    end)
end)

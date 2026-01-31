describe("backend_exec_env", function()
    local backend_exec_env
    local PLUGIN

    before_each(function()
        _G.PLUGIN = {}
        local chunk = assert(loadfile("hooks/backend_exec_env.lua"))
        chunk()
        PLUGIN = _G.PLUGIN
        backend_exec_env = PLUGIN.BackendExecEnv
    end)

    after_each(function()
        _G.PLUGIN = nil
    end)

    describe("PLUGIN:BackendExecEnv", function()
        it("returns empty env_vars for non-postgres tools", function()
            local ctx = {
                install_path = "/path/to/install",
                tool = "mysql",
                version = "1.0.0",
            }

            local result = backend_exec_env(PLUGIN, ctx)

            assert.is_not_nil(result)
            assert.is_table(result.env_vars)
            assert.are.equal(0, #result.env_vars)
        end)

        it("sets up environment variables for postgres tool", function()
            local ctx = {
                install_path = "/path/to/postgres",
                tool = "postgres",
                version = "15.1.0",
            }

            local result = backend_exec_env(PLUGIN, ctx)

            assert.is_not_nil(result)
            assert.is_table(result.env_vars)
            assert.are.equal(5, #result.env_vars)

            local env_map = {}
            for _, env in ipairs(result.env_vars) do
                env_map[env.key] = env.value
            end

            assert.are.equal("/path/to/postgres/bin", env_map.PATH)
            assert.are.equal("/path/to/postgres/data", env_map.PGDATA)
            assert.are.equal("/path/to/postgres/lib", env_map.LD_LIBRARY_PATH)
            assert.are.equal("/path/to/postgres/lib", env_map.DYLD_LIBRARY_PATH)
            assert.are.equal("/path/to/postgres", env_map.PGHOME)
        end)

        it("sets up environment variables for postgresql tool", function()
            local ctx = {
                install_path = "/opt/postgresql",
                tool = "postgresql",
                version = "14.2.0",
            }

            local result = backend_exec_env(PLUGIN, ctx)

            assert.is_not_nil(result)
            assert.is_table(result.env_vars)
            assert.are.equal(5, #result.env_vars)

            local env_map = {}
            for _, env in ipairs(result.env_vars) do
                env_map[env.key] = env.value
            end

            assert.are.equal("/opt/postgresql/bin", env_map.PATH)
            assert.are.equal("/opt/postgresql/data", env_map.PGDATA)
            assert.are.equal("/opt/postgresql", env_map.PGHOME)
        end)

        it("handles Windows-style paths", function()
            local ctx = {
                install_path = "C:\\Users\\test\\postgres",
                tool = "postgres",
                version = "15.1.0",
            }

            local result = backend_exec_env(PLUGIN, ctx)

            assert.is_not_nil(result)
            assert.is_table(result.env_vars)

            local env_map = {}
            for _, env in ipairs(result.env_vars) do
                env_map[env.key] = env.value
            end

            assert.are.equal("C:\\Users\\test\\postgres/bin", env_map.PATH)
            assert.are.equal("C:\\Users\\test\\postgres/data", env_map.PGDATA)
        end)
    end)
end)

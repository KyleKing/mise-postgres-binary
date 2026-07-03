describe("backend_exec_env", function()
    local backend_exec_env
    local PLUGIN

    local function load_plugin(os_type)
        _G.PLUGIN = {}
        _G.RUNTIME = { osType = os_type or "linux" }
        local chunk = assert(loadfile("hooks/backend_exec_env.lua"))
        chunk()
        PLUGIN = _G.PLUGIN
        backend_exec_env = PLUGIN.BackendExecEnv
    end

    after_each(function()
        _G.PLUGIN = nil
        _G.RUNTIME = nil
    end)

    describe("PLUGIN:BackendExecEnv", function()
        it("returns empty env_vars for non-postgres tools", function()
            load_plugin("linux")
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

        it("sets LD_LIBRARY_PATH on linux", function()
            load_plugin("linux")
            local ctx = {
                install_path = "/path/to/postgres",
                tool = "postgres",
                version = "15.1.0",
            }

            local result = backend_exec_env(PLUGIN, ctx)

            assert.is_not_nil(result)
            assert.is_table(result.env_vars)
            assert.are.equal(4, #result.env_vars)

            local env_map = {}
            for _, env in ipairs(result.env_vars) do
                env_map[env.key] = env.value
            end

            assert.are.equal("/path/to/postgres/bin", env_map.PATH)
            assert.are.equal("/path/to/postgres/data", env_map.PGDATA)
            assert.are.equal("/path/to/postgres", env_map.PGHOME)
            assert.are.equal("/path/to/postgres/lib", env_map.LD_LIBRARY_PATH)
            assert.is_nil(env_map.DYLD_LIBRARY_PATH)
        end)

        it("sets DYLD_LIBRARY_PATH on darwin", function()
            load_plugin("darwin")
            local ctx = {
                install_path = "/path/to/postgres",
                tool = "postgres",
                version = "15.1.0",
            }

            local result = backend_exec_env(PLUGIN, ctx)

            assert.is_not_nil(result)
            assert.is_table(result.env_vars)
            assert.are.equal(4, #result.env_vars)

            local env_map = {}
            for _, env in ipairs(result.env_vars) do
                env_map[env.key] = env.value
            end

            assert.are.equal("/path/to/postgres/bin", env_map.PATH)
            assert.are.equal("/path/to/postgres/data", env_map.PGDATA)
            assert.are.equal("/path/to/postgres", env_map.PGHOME)
            assert.are.equal("/path/to/postgres/lib", env_map.DYLD_LIBRARY_PATH)
            assert.is_nil(env_map.LD_LIBRARY_PATH)
        end)

        it("sets no library path env var on windows", function()
            load_plugin("windows")
            local ctx = {
                install_path = "C:\\Users\\test\\postgres",
                tool = "postgres",
                version = "15.1.0",
            }

            local result = backend_exec_env(PLUGIN, ctx)

            assert.is_not_nil(result)
            assert.is_table(result.env_vars)
            assert.are.equal(3, #result.env_vars)

            local env_map = {}
            for _, env in ipairs(result.env_vars) do
                env_map[env.key] = env.value
            end

            assert.are.equal("C:\\Users\\test\\postgres/bin", env_map.PATH)
            assert.are.equal("C:\\Users\\test\\postgres/data", env_map.PGDATA)
            assert.are.equal("C:\\Users\\test\\postgres", env_map.PGHOME)
            assert.is_nil(env_map.LD_LIBRARY_PATH)
            assert.is_nil(env_map.DYLD_LIBRARY_PATH)
        end)

        it("sets up environment variables for postgresql tool alias", function()
            load_plugin("linux")
            local ctx = {
                install_path = "/opt/postgresql",
                tool = "postgresql",
                version = "14.2.0",
            }

            local result = backend_exec_env(PLUGIN, ctx)

            assert.is_not_nil(result)
            assert.is_table(result.env_vars)
            assert.are.equal(4, #result.env_vars)

            local env_map = {}
            for _, env in ipairs(result.env_vars) do
                env_map[env.key] = env.value
            end

            assert.are.equal("/opt/postgresql/bin", env_map.PATH)
            assert.are.equal("/opt/postgresql/data", env_map.PGDATA)
            assert.are.equal("/opt/postgresql", env_map.PGHOME)
            assert.are.equal("/opt/postgresql/lib", env_map.LD_LIBRARY_PATH)
        end)
    end)
end)

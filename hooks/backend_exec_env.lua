--- Sets up PostgreSQL environment variables for the installed tool
--- @param ctx table Context containing install_path, tool, and version
--- @return table Table with env_vars array
function PLUGIN:BackendExecEnv(ctx)
    local install_path = ctx.install_path
    local tool = ctx.tool

    -- Only handle postgres/postgresql tools
    if tool ~= "postgres" and tool ~= "postgresql" then
        return { env_vars = {} }
    end

    -- PostgreSQL-specific environment variables
    local env_vars = {
        -- Add PostgreSQL bin directory to PATH
        {
            key = "PATH",
            value = install_path .. "/bin",
        },

        -- Set PGDATA to the data directory
        {
            key = "PGDATA",
            value = install_path .. "/data",
        },

        -- Add library path for dynamic linking (Linux)
        {
            key = "LD_LIBRARY_PATH",
            value = install_path .. "/lib",
        },

        -- Add library path for dynamic linking (macOS)
        {
            key = "DYLD_LIBRARY_PATH",
            value = install_path .. "/lib",
        },

        -- Optional: Set PGHOME for tools that expect it
        {
            key = "PGHOME",
            value = install_path,
        },
    }

    return { env_vars = env_vars }
end

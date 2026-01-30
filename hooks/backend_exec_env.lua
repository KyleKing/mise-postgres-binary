--- Sets up PostgreSQL environment variables for the installed tool
--- @param ctx table Context containing install_path, tool, and version
--- @return table Table with env_vars array
function PLUGIN:BackendExecEnv(ctx)
    local install_path = ctx.install_path
    local tool = ctx.tool

    if tool ~= "postgres" and tool ~= "postgresql" then
        return { env_vars = {} }
    end

    local env_vars = {
        {
            key = "PATH",
            value = install_path .. "/bin",
        },
        {
            key = "PGDATA",
            value = install_path .. "/data",
        },
        {
            key = "LD_LIBRARY_PATH",
            value = install_path .. "/lib",
        },
        {
            key = "DYLD_LIBRARY_PATH",
            value = install_path .. "/lib",
        },
        {
            key = "PGHOME",
            value = install_path,
        },
    }

    return { env_vars = env_vars }
end

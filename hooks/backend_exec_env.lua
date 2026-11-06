--- Sets up PostgreSQL environment variables for the installed tool
--- @param ctx table Context containing install_path, tool, and version
--- @return table Table with env_vars array
function PLUGIN:BackendExecEnv(ctx)
    local install_path = ctx.install_path
    local tool = ctx.tool

    if tool ~= "postgres" and tool ~= "postgresql" then
        return { env_vars = {} }
    end

    local os_type = RUNTIME and RUNTIME.osType and RUNTIME.osType:lower() or "linux"

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
            key = "PGHOME",
            value = install_path,
        },
    }

    if os_type == "linux" then
        table.insert(env_vars, { key = "LD_LIBRARY_PATH", value = install_path .. "/lib" })
    elseif os_type == "darwin" then
        table.insert(env_vars, { key = "DYLD_LIBRARY_PATH", value = install_path .. "/lib" })
    end

    return { env_vars = env_vars }
end

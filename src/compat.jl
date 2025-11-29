function extract_kwargs(kwargs, keys)
    return (k => v for (k, v) in pairs(kwargs) if k in keys)
end

extract_fields(x) = Dict(String(name) => getfield(x, name) for name in fieldnames(typeof(x)))

# Trailing directory separator matters for `basename`, so let's strip it to
# avoid confusion
strip_path_separator(path::AbstractString) = isdirpath(path) ? dirname(path) : path

function valid_dl_path(path, platform)
    try
        parse_dl_name_version(path, os(platform))
        return true
    catch
        return false
    end
end

# If we don't have `stdlib_version` from Pkg, recreate it ourselves
if !isdefined(Pkg.Types, :stdlib_version)
    function stdlib_version(uuid::Base.UUID, julia_version::Union{VersionNumber,Nothing})::Union{VersionNumber,Nothing}
        last_stdlibs = Pkg.Types.get_last_stdlibs(julia_version)
        if !(uuid in keys(last_stdlibs))
            return nothing
        end
        return last_stdlibs[uuid][2]
    end
else
    const stdlib_version = Pkg.Types.stdlib_version
end

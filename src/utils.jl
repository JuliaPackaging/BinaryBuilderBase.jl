# The functions in this file may not be used anywhere in this package but may
# needed by different modules of BinaryBuilder.jl

with_logfile(f::Function, prefix::Prefix, name::String) = with_logfile(f, joinpath(logdir(prefix), name))
function with_logfile(f::Function, logfile::String)
    mkpath(dirname(logfile))

    # If it's already a file, remove it, as it is probably an incorrect symlink
    if isfile(logfile)
        rm(logfile; force=true)
    end
    open(logfile, "w") do io
        f(io)
    end
end

"""
    get_concrete_platform(platform::Platform, shards::Vector{CompilerShard})

Return the concrete platform for the given `platform` based on the GCC compiler
ABI in the `shards`.
"""
function get_concrete_platform(platform::Platform, shards::Vector{CompilerShard})
    # We want to get dependencies that have exactly the same GCC ABI as the
    # chosen compiler, otherwise we risk, e.g., to build in an environment
    # with libgfortran3 a dependency built with libgfortran5.
    # `concrete_platform` is needed only to setup the dependencies and the
    # runner.  We _don't_ want the platform passed to `audit()` or
    # `package()` to be more specific than it is.
    concrete_platform = deepcopy(platform)
    gccboostrap_shard_idx = findfirst(x -> x.name == "GCCBootstrap" &&
                                      arch(x.target) == arch(platform) &&
                                      libc(x.target) == libc(platform),
                                      shards)
    if !isnothing(gccboostrap_shard_idx)
        cs = shards[gccboostrap_shard_idx]
        concrete_platform["libgfortran_version"] = string(preferred_libgfortran_version(platform, cs))
        concrete_platform["cxxstring_abi"] = string(preferred_cxxstring_abi(platform, cs))
        if haskey(cs.target, "os_version")
            concrete_platform["os_version"] = cs.target["os_version"]
        end
    end
    return concrete_platform
end

"""
    get_concrete_platform(platform::AbstractPlatform;
                          preferred_gcc_version = nothing,
                          preferred_llvm_version = nothing,
                          compilers = nothing)

Return the concrete platform for the given `platform` based on the GCC compiler
ABI.  The set of shards is chosen by the keyword arguments (see [`choose_shards`](@ref)).
"""
function get_concrete_platform(platform::AbstractPlatform; kwargs...)
    shards = choose_shards(platform; kwargs...)
    return get_concrete_platform(platform, shards)
end

# XXX: we want the AnyPlatform to look like `x86_64-linux-musl`,
get_concrete_platform(::AnyPlatform, shards::Vector{CompilerShard}) =
    get_concrete_platform(default_host_platform, shards)

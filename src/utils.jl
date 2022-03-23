# The functions in this file may not be used anywhere in this package but may
# needed by different modules of BinaryBuilder.jl

using Base.BinaryPlatforms: arch_march_isa_mapping, set_compare_strategy!
using Base.BinaryPlatforms.CPUID

with_logfile(f::Function, prefix::Prefix, name::String; subdir="") = with_logfile(f, joinpath(logdir(prefix; subdir), name))
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
                                      arch(x.target::Platform) == arch(platform) &&
                                      libc(x.target::Platform) == libc(platform),
                                      shards)
    if !isnothing(gccboostrap_shard_idx)
        cs = shards[gccboostrap_shard_idx]
        concrete_platform["libgfortran_version"] = string(preferred_libgfortran_version(platform, cs))
        concrete_platform["cxxstring_abi"] = string(preferred_cxxstring_abi(platform, cs))
        if haskey(cs.target::Platform, "os_version")
            concrete_platform["os_version"] = (cs.target::Platform)["os_version"]
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

# We want the AnyPlatform to look like `default_host_platform`,
get_concrete_platform(::AnyPlatform, shards::Vector{CompilerShard}) =
    get_concrete_platform(default_host_platform, shards)

function march_comparison_strategy(a::String, b::String, a_requested::Bool, b_requested::Bool)
    # If both b and a requested, then we fall back to equality:
    if a_requested && b_requested
        return a == b
    end

    function get_arch_isa(isa_name::String)
        for (arch, isas) in arch_march_isa_mapping
            for (name, isa) in isas
                name == isa_name && return arch, isa
            end
        end
        return nothing, nothing
    end

    a_arch, a_isa = get_arch_isa(a)
    b_arch, b_isa = get_arch_isa(b)
    if any(isnothing, (a_arch, b_arch)) || a_arch != b_arch
        # Architectures are definitely not compatible, exit early
        return false
    end

    if a_requested
        # ISA `b` is compatible with ISA `a` only if it's a subset of `a`
        return b_isa ≤ a_isa
    else
        # ISA `a` is compatible with ISA `b` only if it's a subset of `b`
        return a_isa ≤ b_isa
    end
end

function augment_microarchitecture!(platform::Platform)
    if haskey(platform, "march")
        set_compare_strategy!(platform, "march", march_comparison_strategy)
        return platform
    end

    host_arch = arch(HostPlatform())
    host_isas = arch_march_isa_mapping[host_arch]
    idx = findlast(((name, isa),) -> isa <= CPUID.cpu_isa(), host_isas)
    platform["march"] = first(host_isas[idx])
    set_compare_strategy!(platform, "march", march_comparison_strategy)
    return platform
end

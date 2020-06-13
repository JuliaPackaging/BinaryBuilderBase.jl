using Pkg.BinaryPlatforms

export AnyPlatform, ExtendedPlatform

"""
    AnyPlatform()

A special platform to be used to build platform-independent tarballs, like those
containing only header files.  [`FileProduct`](@ref) is the only product type
allowed with this platform.
"""
struct AnyPlatform <: Platform end
abi_agnostic(p::AnyPlatform) = p
Pkg.BinaryPlatforms.platform_name(::AnyPlatform) = "AnyPlatform"
Pkg.BinaryPlatforms.triplet(::AnyPlatform) = "any"
# Fallback on x86_64-linux-musl, but this shouldn't really matter in practice.
Pkg.BinaryPlatforms.arch(::AnyPlatform) = arch(Linux(:x86_64, libc=:musl))
Base.show(io::IO, ::AnyPlatform) = print(io, "AnyPlatform()")

## The extended platforms, to represent platforms beyond the standard ones in
## Pkg.BinaryPlatforms.
"""
    ExtendedPlatform(p::Platform; kwargs...)

Extend the given platform with extra information.  The key and the value can be
arbitrary, with the conditions that they should only use alhanumerical
characters, the underscore, or the dot (the latter only for the value).

This type is, for example, used to tag a standard platform from
`Pkg.BinaryPlatforms` with additional features besides the C library or the
compiler ABI.

```jldoctest
julia> ExtendedPlatform(Linux(:x86_64; libc=:glibc, compiler_abi=CompilerABI(; libgfortran_version=v"4")); march = "avx", cuda = "9.2")
ExtendedPlatform(Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"4.0.0")); march="avx", cuda="9.2")
```
"""
struct ExtendedPlatform{P<:Platform} <: Platform
    p::P
    ext::Dict{String,String}
end
ExtendedPlatform(p::Platform; kwargs...) =
    ExtendedPlatform(p, Dict(string(k) => string(v) for (k, v) in pairs(kwargs)))
function ExtendedPlatform(p::ExtendedPlatform; kwargs...)
    for (k, v) in pairs(kwargs)
        key = String(k)
        if haskey(p.ext, key) && p.ext[key] != v
            error("The input platform has an incompatible feature $(key => p.ext[key])")
        end
    end
    ExtendedPlatform(p.p, merge(p.ext, Dict(string(k) => string(v) for (k, v) in pairs(kwargs))))
end

Pkg.BinaryPlatforms.platform_name(::ExtendedPlatform) = "ExtendedPlatform"
Pkg.BinaryPlatforms.arch(ep::ExtendedPlatform) = arch(ep.p)
Pkg.BinaryPlatforms.libc(ep::ExtendedPlatform) = libc(ep.p)
Pkg.BinaryPlatforms.call_abi(ep::ExtendedPlatform) = call_abi(ep.p)
Pkg.BinaryPlatforms.compiler_abi(ep::ExtendedPlatform) = compiler_abi(ep.p)
Pkg.BinaryPlatforms.triplet(ep::ExtendedPlatform) =
    triplet(ep.p) * join(["-$(k)+$(ep.ext[k])" for k in sort(collect(keys(ep.ext)))])

# This function also strips out the extra features of the type
abi_agnostic(ep::ExtendedPlatform) = abi_agnostic(ep.p)

function Base.show(io::IO, ep::ExtendedPlatform)
    print(io, BinaryPlatforms.platform_name(ep), "(", ep.p)
    length(ep.ext) > 0 && print(io, ";")
    join(io, [" $(k)=$(repr(v))" for (k, v) in ep.ext], ",")
    print(io, ")")
end

# Vendor Pkg.BinaryPlatforms.platform_key_abi, with a different name.  The
# difference with the original version is that if the triplet can't be parse we
# return `nothing`, wthout issuing a warning
function tryparse_standard_platform(machine::AbstractString)
    # We're going to build a mondo regex here to parse everything:
    arch_mapping = Dict(
        :x86_64 => "(x86_|amd)64",
        :i686 => "i\\d86",
        :aarch64 => "aarch64",
        :armv7l => "arm(v7l)?", # if we just see `arm-linux-gnueabihf`, we assume it's `armv7l`
        :armv6l => "armv6l",
        :powerpc64le => "p(ower)?pc64le",
    )
    platform_mapping = Dict(
        :darwin => "-apple-darwin[\\d\\.]*",
        :freebsd => "-(.*-)?freebsd[\\d\\.]*",
        :mingw32 => "-w64-mingw32",
        :linux => "-(.*-)?linux",
    )
    libc_mapping = Dict(
        :libc_nothing => "",
        :glibc => "-gnu",
        :musl => "-musl",
    )
    call_abi_mapping = Dict(
        :call_abi_nothing => "",
        :eabihf => "eabihf",
    )
    libgfortran_version_mapping = Dict(
        :libgfortran_nothing => "",
        :libgfortran3 => "(-libgfortran3)|(-gcc4)", # support old-style `gccX` versioning
        :libgfortran4 => "(-libgfortran4)|(-gcc7)",
        :libgfortran5 => "(-libgfortran5)|(-gcc8)",
    )
    libstdcxx_version_mapping = Dict(
        :libstdcxx_nothing => "",
        # This is sadly easier than parsing out the digit directly
        (Symbol("libstdcxx$(idx)") => "-libstdcxx$(idx)" for idx in 18:26)...,
    )
    cxxstring_abi_mapping = Dict(
        :cxxstring_nothing => "",
        :cxx03 => "-cxx03",
        :cxx11 => "-cxx11",
    )

    # Helper function to collapse dictionary of mappings down into a regex of
    # named capture groups joined by "|" operators
    c(mapping) = string("(",join(["(?<$k>$v)" for (k, v) in mapping], "|"), ")")

    triplet_regex = Regex(string(
        "^",
        c(arch_mapping),
        c(platform_mapping),
        c(libc_mapping),
        c(call_abi_mapping),
        c(libgfortran_version_mapping),
        c(libstdcxx_version_mapping),
        c(cxxstring_abi_mapping),
        "\$",
    ))

    m = match(triplet_regex, machine)
    if m !== nothing
        # Helper function to find the single named field within the giant regex
        # that is not `nothing` for each mapping we give it.
        get_field(m, mapping) = begin
            for k in keys(mapping)
                if m[k] !== nothing
                    strk = string(k)
                    # Convert our sentinel `nothing` values to actual `nothing`
                    if endswith(strk, "_nothing")
                        return nothing
                    end
                    # Convert libgfortran/libstdcxx version numbers
                    if startswith(strk, "libgfortran")
                        return VersionNumber(parse(Int,strk[12:end]))
                    elseif startswith(strk, "libstdcxx")
                        return VersionNumber(3, 4, parse(Int,strk[10:end]))
                    else
                        return k
                    end
                end
            end
        end

        # Extract the information we're interested in:
        arch = get_field(m, arch_mapping)
        platform = get_field(m, platform_mapping)
        libc = get_field(m, libc_mapping)
        call_abi = get_field(m, call_abi_mapping)
        libgfortran_version = get_field(m, libgfortran_version_mapping)
        libstdcxx_version = get_field(m, libstdcxx_version_mapping)
        cxxstring_abi = get_field(m, cxxstring_abi_mapping)

        # First, figure out what platform we're dealing with, then sub that off
        # to the appropriate constructor.  If a constructor runs into trouble,
        # catch the error and return `UnknownPlatform()` here to be nicer to client code.
        ctors = Dict(:darwin => MacOS, :mingw32 => Windows, :freebsd => FreeBSD, :linux => Linux)
        try
            T = ctors[platform]
            compiler_abi = CompilerABI(;
                libgfortran_version=libgfortran_version,
                libstdcxx_version=libstdcxx_version,
                cxxstring_abi=cxxstring_abi
            )
            return T(arch, libc=libc, call_abi=call_abi, compiler_abi=compiler_abi)
        catch
        end
    end

    return nothing
end

function Base.tryparse(::Type{ExtendedPlatform}, str::AbstractString)
    split_str = split(str, "-")
    extra_str = String[]
    base_platform = platform_key_abi()
    # Try to parse the longest string possible with the standard parser
    while length(split_str) > 0
        base_platform = tryparse_standard_platform(join(split_str, '-'))
        if base_platform !== nothing
            break
        end
        push!(extra_str, pop!(split_str))
    end
    if base_platform === nothing
        # We couldn't find a standard platform in the string, give up
        return nothing
    end
    extra = Dict{String,String}()
    # Build up the extra features
    for kv in extra_str
        # Split the extra feature with the delimiter we expect between the key
        # and the value
        key_value = split(kv, '+')
        if length(key_value) != 2
            # The string doesn't represent a key-value pair, give up
            return nothing
        end
        extra[key_value[1]] = key_value[2]
    end
    # Return the extended platform parsed
    ExtendedPlatform(base_platform, extra)
end

function Base.parse(T::Type{ExtendedPlatform}, str::AbstractString)
    parsed = tryparse(T, str)
    if parsed === nothing
        throw(ArgumentError("Cannot parse \"$(str)\" as an $(T)"))
    end
    return parsed
end

Base.:(==)(a::ExtendedPlatform, b::ExtendedPlatform) = a.p == b.p && a.ext == b.ext

# Extending the same platform: match only if the base platforms match and the
# same keys in the dictionaries have the same values
Pkg.BinaryPlatforms.platforms_match(a::ExtendedPlatform{P}, b::ExtendedPlatform{P}) where {P<:Platform} =
    platforms_match(a.p, b.p) &&  all(a.ext[k] == b.ext[k] for k in keys(a.ext) ∩ keys(b.ext))
# The wrapped platform is the same as the other one: the arguments match if the
# wrapper platform and the other one match
Pkg.BinaryPlatforms.platforms_match(a::ExtendedPlatform{P}, b::P) where {P<:Platform} = platforms_match(a.p, b)
Pkg.BinaryPlatforms.platforms_match(a::P, b::ExtendedPlatform{P}) where {P<:Platform} = platforms_match(a, b.p)
# Extending a platform different from the other one: do not match
Pkg.BinaryPlatforms.platforms_match(a::ExtendedPlatform{P1}, b::P2) where {P1<:Platform, P2<:Platform} = false
Pkg.BinaryPlatforms.platforms_match(a::P1, b::ExtendedPlatform{P2}) where {P1<:Platform, P2<:Platform} = false
# Extending different platforms: do not match
Pkg.BinaryPlatforms.platforms_match(a::ExtendedPlatform{P1}, b::ExtendedPlatform{P2}) where {P1<:Platform, P2<:Platform} = false

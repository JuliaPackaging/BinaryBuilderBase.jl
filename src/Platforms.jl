using Pkg.Artifacts, Pkg.BinaryPlatforms, Logging

export AnyPlatform, ExtendedPlatform, base_platform

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

const ARCHITECTURE_FLAGS = begin
    # Better be always explicit about `-march` & `-mtune`:
    # https://lemire.me/blog/2018/07/25/it-is-more-complicated-than-i-thought-mtune-march-in-gcc/
    march_flags(arch) = ["-m$(f)=$(arch)" for f in ("arch", "tune")]
    Dict(
        :x86_64 => Dict(
            "x86_64" => ["-march=x86-64", "-mtune=generic"],
            "avx" => march_flags("sandybridge"),
            "avx2" => march_flags("haswell"),
            "avx512" => march_flags("skylake-avx512"),
        ),
        :armv7l => Dict(
            "armv7l" => ["-march=armv7-a", "-mtune=generic-armv7-a"],
            "neon" => ["-march=armv7-a+neon", "-mtune=generic-armv7-a"],
            "vfp4" => ["-march=armv7-a+neon-vfpv4", "-mtune=generic-armv7-a"],
        ),
        :aarch64 => Dict(
            "armv8" => ["-march=armv8-a", "-mtune=cortex-a57"],
            "thunderx2" => ["-march=armv8.1-a", "-mtune=thunderx2t99"],
            "carmel" => ["-march=armv8.2-a+crypto+fp16+sha2+aes", "-mtune=cortex-a75"],
        ),
    )
end

"""
    ExtendedPlatform(p::Platform; kwargs...)

Extend a `Pkg.BinaryPlatforms.Platform` object with extra key-value mappings.
Arbitrary `String` values are supported, with the following constraints:

* the key cannot be any of "os", "arch", "libc", "libgfortran_version",
  "libstdcxx_version", "cxxstring_abi";
* if the key is called "march", only specific values are allowed, depending on
  what is the base platform,
* all strings should only use alphanumeric characters, the underscore, or the
  dot (the latter only for the value).

This type is, for example, used to tag a standard platform from
`Pkg.BinaryPlatforms` with additional features besides the C library or the
compiler ABI.

```jldoctest
julia> using BinaryBuilderBase

julia> ExtendedPlatform(Linux(:x86_64; libc=:glibc, compiler_abi=CompilerABI(; libgfortran_version=v"4")); march = "avx", cuda = "9.2")
ExtendedPlatform(Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"4.0.0")); march="avx", cuda="9.2")
```
"""
struct ExtendedPlatform{P<:Platform} <: Platform
    p::P
    ext::Dict{String,String}
    function ExtendedPlatform{P}(p::P, ext::Dict{String,String}) where {P<:Platform}
        for (k, v) in ext
            if k in ("os", "arch", "libc", "libgfortran_version", "libstdcxx_version", "cxxstring_abi")
                # Throw an error if the key has a special meaning that would
                # make it ambiguous when running `Pkg.Artifacts.pack_platform!`.
                # This is the list of keys that are used there
                throw(ArgumentError("Invalid feature called \"$(k)\""))
            end
            # Validate special keys
            if k == "march" && (arch(p) ∉ keys(ARCHITECTURE_FLAGS) || v ∉ keys(ARCHITECTURE_FLAGS[arch(p)]))
                throw(ArgumentError("Key \"$(k)\" cannot have value \"$(v)\" for platform $(p)"))
            end
            # Make sure the key and the value don't have '+' in them
            if occursin('+', k) || occursin('+', v)
                throw(ArgumentError("The key and the value cannot contain the + sign"))
            end
        end
        return new(p, ext)
    end
end
ExtendedPlatform(p::P, ext::Dict{String,String}) where {P<:Platform} =
    ExtendedPlatform{P}(p, ext)
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

base_platform(p::Platform) = p
base_platform(ep::ExtendedPlatform) = ep.p
march(::Platform; default=nothing) = default
march(p::ExtendedPlatform; default = nothing) = get(p.ext, "march", default)

for f in (:isapple, :islinux, :iswindows, :isbsd)
    @eval Sys.$f(ep::ExtendedPlatform) = Sys.$f(base_platform(ep))
end

Pkg.BinaryPlatforms.platform_name(::ExtendedPlatform) = "ExtendedPlatform"
Pkg.BinaryPlatforms.arch(ep::ExtendedPlatform) = arch(base_platform(ep))
Pkg.BinaryPlatforms.libc(ep::ExtendedPlatform) = libc(base_platform(ep))
Pkg.BinaryPlatforms.call_abi(ep::ExtendedPlatform) = call_abi(base_platform(ep))
Pkg.BinaryPlatforms.compiler_abi(ep::ExtendedPlatform) = compiler_abi(base_platform(ep))
Pkg.BinaryPlatforms.triplet(ep::ExtendedPlatform) =
    triplet(base_platform(ep)) * join(["-$(k)+$(ep.ext[k])" for k in sort(collect(keys(ep.ext)))])
Pkg.BinaryPlatforms.platform_dlext(p::ExtendedPlatform) = platform_dlext(base_platform(p))

# Extending the same platform: match only if the base platforms match and the
# same keys in the dictionaries have the same values
Pkg.BinaryPlatforms.platforms_match(a::ExtendedPlatform{P}, b::ExtendedPlatform{P}) where {P<:Platform} =
    platforms_match(base_platform(a), base_platform(b)) &&  all(a.ext[k] == b.ext[k] for k in keys(a.ext) ∩ keys(b.ext))
# The wrapped platform is the same as the other one: the arguments match if the
# wrapper platform and the other one match
Pkg.BinaryPlatforms.platforms_match(a::ExtendedPlatform{P}, b::P) where {P<:Platform} = platforms_match(base_platform(a), b)
Pkg.BinaryPlatforms.platforms_match(a::P, b::ExtendedPlatform{P}) where {P<:Platform} = platforms_match(a, base_platform(b))
# Extending a platform different from the other one: do not match
Pkg.BinaryPlatforms.platforms_match(a::ExtendedPlatform{P1}, b::P2) where {P1<:Platform, P2<:Platform} = false
Pkg.BinaryPlatforms.platforms_match(a::P1, b::ExtendedPlatform{P2}) where {P1<:Platform, P2<:Platform} = false
# Extending different platforms: do not match
Pkg.BinaryPlatforms.platforms_match(a::ExtendedPlatform{P1}, b::ExtendedPlatform{P2}) where {P1<:Platform, P2<:Platform} = false

Base.:(==)(a::ExtendedPlatform, b::ExtendedPlatform) = base_platform(a) == base_platform(b) && a.ext == b.ext

# This function also strips out the extra features of the type
abi_agnostic(ep::ExtendedPlatform) = abi_agnostic(base_platform(ep))

function Base.show(io::IO, ep::ExtendedPlatform)
    print(io, BinaryPlatforms.platform_name(ep), "(", base_platform(ep))
    length(ep.ext) > 0 && print(io, ";")
    join(io, [" $(k)=$(repr(v))" for (k, v) in ep.ext], ",")
    print(io, ")")
end

function tryparse_standard_platform(machine::AbstractString)
    p = with_logger(NullLogger()) do
        BinaryPlatforms.platform_key_abi(machine)
    end
    if isa(p, UnknownPlatform)
        return nothing
    end
    return p
end

function Base.tryparse(::Type{ExtendedPlatform}, str::AbstractString)
    # Fast-track `AnyPlatform`
    if str == "any"
        return AnyPlatform()
    end
    split_str = split(str, "-")
    idx = findfirst(str -> occursin("+", str), split_str)
    if idx === nothing
        # There are no key-value pairs, parse the entire string with
        # `tryparse_standard_platform`
        return tryparse_standard_platform(str)
    end
    base_platform = tryparse_standard_platform(join(split_str[1:max(1, idx - 1)], '-'))
    if base_platform === nothing
        return nothing
    end
    extra = Dict{String,String}()
    # Build up the extra features
    for kv in split_str[idx:end]
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

function Pkg.Artifacts.pack_platform!(meta::Dict, p::ExtendedPlatform)
    for (k, v) in p.ext
        meta[k] = v
    end
    # We call this method at the end to make extra sure the keys above don't
    # override the default ones
    Artifacts.pack_platform!(meta, base_platform(p))
end

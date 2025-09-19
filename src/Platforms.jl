using Base.BinaryPlatforms
using OrderedCollections

export AnyPlatform

"""
    AnyPlatform()

A special platform to be used to build platform-independent tarballs, like those
containing only header files.  [`FileProduct`](@ref) is the only product type
allowed with this platform.
"""
struct AnyPlatform <: AbstractPlatform end
Base.BinaryPlatforms.tags(p::AnyPlatform) = Dict{String,String}()
Base.BinaryPlatforms.triplet(::AnyPlatform) = "any"
Base.BinaryPlatforms.arch(::AnyPlatform) = "any"
Base.BinaryPlatforms.os(::AnyPlatform) = "any"
nbits(::AnyPlatform) = nbits(default_host_platform)
proc_family(::AnyPlatform) = "any"
Base.show(io::IO, ::AnyPlatform) = print(io, "AnyPlatform")

function _agnostic(p::Platform, keeps)
    filtered_tags = (Symbol(k) => convert(String, v) for (k, v) in tags(p) if k ∈ keeps)
    return Platform(arch(p)::String, os(p)::String; filtered_tags...)
end
_agnostic(p::AnyPlatform, _) = p

"""
    abi_agnostic(p::AbstractPlatform)

Strip out any tags that are not the basic annotations like `libc` and `call_abi`.
"""
abi_agnostic(p::AbstractPlatform) = _agnostic(p, ("libc", "call_abi", "os_version"))

"""
    libabi_agnostic(p::AbstractPlatform)

Like `abi_agnostic`, but keep the sanitizer ABI tags.
"""
libabi_agnostic(p::AbstractPlatform) = _agnostic(p, ("libc", "call_abi", "os_version", "sanitize"))

"""
    os_version_agnostic(p::AbstractPlatform)

Strip out an `os_version` tag if it exists.
"""
os_version_agnostic(p::AbstractPlatform) =
    _agnostic(p, filter(!in(("arch", "os", "os_version")), keys(tags(p))))

platforms_match_with_sanitize(a::AbstractPlatform, b::AbstractPlatform) =
    platforms_match(a, b) && sanitize(a) == sanitize(b)
function platforms_match_with_sanitize(a::AbstractString, b::AbstractPlatform)
    return platforms_match_with_sanitize(parse(Platform, a), b)
end
function platforms_match_with_sanitize(a::AbstractPlatform, b::AbstractString)
    return platforms_match_with_sanitize(a, parse(Platform, b))
end

"""
    platform_exeext(p::AbstractPlatform)

Get the executable extension for the given Platform.  Includes the leading `.`.
"""
platform_exeext(p::AbstractPlatform) = Sys.iswindows(p) ? ".exe" : ""


# Helper parsing function: it extends `parse(Platform, p)` by supporting
# `AnyPlatform` as well.
function parse_platform(p::AbstractString)
    if p == "any"
        AnyPlatform()
    elseif p == "host"
        HostPlatform()
    else
        parse(Platform, p; validate_strict=true)
    end
end

# Recursively test for key presence in nested dicts
function haskeys(d, keys...)
    for key in keys
        if !haskey(d, key)
            return false
        end
        d = d[key]
    end
    return true
end
function get_march_flags(arch::String, march::String, compiler::String)
    # First, check if it's in the `"common"`
    if haskeys(ARCHITECTURE_FLAGS, "common", arch, march)
        return ARCHITECTURE_FLAGS["common"][arch][march]
    end
    if haskeys(ARCHITECTURE_FLAGS, compiler, arch, march)
        return ARCHITECTURE_FLAGS[compiler][arch][march]
    end
    # If this march cannot be found, return no flags
    return String[]
end
# If `march` is `nothing`, that means get the "generic" flags
function get_march_flags(arch::String, march::Nothing, compiler::String)
    return get_march_flags(arch, first(get_all_march_names(arch)), compiler)
end
function get_all_arch_names()
    # We don't use Base.BinaryPlatforms.arch_march_isa_mapping here so that
    # we can experiment with adding new architectures in BB before they land in Julia Base.
    return unique(vcat(
        collect(keys(ARCHITECTURE_FLAGS["common"])),
        collect(keys(ARCHITECTURE_FLAGS["gcc"])),
        collect(keys(ARCHITECTURE_FLAGS["clang"])),
    ))
end
function get_all_march_names(arch::String)
    return unique(vcat(
        collect(keys(get(ARCHITECTURE_FLAGS["common"], arch, Dict{String,String}()))),
        collect(keys(get(ARCHITECTURE_FLAGS["gcc"], arch, Dict{String,String}()))),
        collect(keys(get(ARCHITECTURE_FLAGS["clang"], arch, Dict{String,String}()))),
    ))
end

# NOTE: This needs to be kept in sync with `ISAs_by_family` in `Base.BinaryPlatforms.CPUID`
# This will allow us to detect these names at runtime and select artifacts accordingly.
const ARCHITECTURE_FLAGS = Dict(
    # Many compiler flags are the same across clang and gcc, store those in "common"
    "common" => Dict(
        "i686" => OrderedDict(
            "pentium4" => ["-march=pentium4", "-mtune=generic"],
            "prescott" => ["-march=prescott", "-mtune=prescott"],
        ),
        "x86_64" => OrderedDict(
            # Better be always explicit about `-march` & `-mtune`:
            # https://lemire.me/blog/2018/07/25/it-is-more-complicated-than-i-thought-mtune-march-in-gcc/
            "x86_64" => ["-march=x86-64", "-mtune=generic"],
            "avx"    => ["-march=sandybridge", "-mtune=sandybridge"],
            "avx2"   => ["-march=haswell", "-mtune=haswell"],
            "avx512" => ["-march=skylake-avx512", "-mtune=skylake-avx512"],
        ),
        "armv6l" => OrderedDict(
            # This is the only known armv6l chip that runs Julia, so it's the only one we care about.
            "arm1176jzfs" => ["-mcpu=arm1176jzf-s", "-mfpu=vfp", "-mfloat-abi=hard"],
        ),
        "armv7l" => OrderedDict(
            # Base armv7l architecture, with the most basic of FPUs
            "armv7l"   => ["-march=armv7-a", "-mtune=generic-armv7-a", "-mfpu=vfpv3", "-mfloat-abi=hard"],
            # armv7l plus NEON and vfpv4, (Raspberry Pi 2B+, RK3328, most boards Elliot has access to)
            "neonvfpv4" => ["-mcpu=cortex-a53", "-mfpu=neon-vfpv4", "-mfloat-abi=hard"],
        ),
        "aarch64" => OrderedDict(
            # For GCC, see: <https://gcc.gnu.org/onlinedocs/gcc/AArch64-Options.html>.  For
            # LLVM, for the list of features see
            # <https://github.com/llvm/llvm-project/blob/1bcc28b884ff4fbe2ecc011b8ea2b84e7987167b/llvm/include/llvm/Support/AArch64TargetParser.def>
            # and
            # <https://github.com/llvm/llvm-project/blob/85e9b2687a13d1908aa86d1b89c5ce398a06cd39/llvm/lib/Target/AArch64/AArch64.td>.
            # Run `clang --print-supported-cpus` for the list of values of `-mtune`.
            "armv8_0"        => ["-march=armv8-a", "-mcpu=cortex-a57"],
            "armv8_1"        => ["-march=armv8.1-a", "-mcpu=thunderx2t99"],
            "armv8_2_crypto" => ["-march=armv8.2-a+aes+sha2", "-mcpu=cortex-a76"],
            "a64fx"          => ["-mcpu=a64fx"],
        ),
        "powerpc64le" => OrderedDict(
            "power8"  => ["-mcpu=power8", "-mtune=power8"],
            # Note that power9 requires GCC 6+, and we need CPUID for this
            #"power9"  => ["-mcpu=power9", "-mtune=power9"],
            # Eventually, we'll support power10, once we have compilers that support it.
            #"power10" => ["-mcpu=power10", "-mtune=power10"],
        ),
        "riscv64" => OrderedDict(
            "riscv64" => ["-march=rv64gc", "-mabi=lp64d"],
        ),
    ),
    "gcc" => Dict(
        "aarch64" => OrderedDict(
            "apple_m1"       => ["-march=armv8.5-a+aes+sha2+sha3+fp16fml+fp16+rcpc+dotprod", "-mcpu=cortex-a76"],
        ),
    ),
    "clang" => Dict(
        "aarch64" => OrderedDict(
            "apple_m1"       => ["-mcpu=apple-m1"],
        ),
    ),
)
march(p::AbstractPlatform; default=nothing) = get(tags(p), "march", default)
sanitize(p::AbstractPlatform; default=nothing) = get(tags(p), "sanitize", default)

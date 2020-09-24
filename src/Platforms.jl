using Base.BinaryPlatforms

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
nbits(::AnyPlatform) = 64
proc_family(::AnyPlatform) = "any"
Base.show(io::IO, ::AnyPlatform) = print(io, "AnyPlatform")

"""
    abi_agnostic(p::AbstractPlatform)

Strip out any tags that are not the basic annotations like `libc` and `call_abi`.
"""
function abi_agnostic(p::Platform)
    keeps = ("libc", "call_abi", "os_version")
    filtered_tags = Dict(Symbol(k) => v for (k, v) in tags(p) if k ∈ keeps)
    return Platform(arch(p), os(p); filtered_tags...)
end
abi_agnostic(p::AnyPlatform) = p


"""
    platform_exeext(p::AbstractPlatform)

Get the executable extension for the given Platform.  Includes the leading `.`.
"""
platform_exeext(p::AbstractPlatform) = Sys.iswindows(p) ? ".exe" : ""


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
        "i686" => Dict(
            "i686" => ["-march=i686", "-mtune=generic"]
            "prescott" => ["-march=prescott", "-mtune=prescott"],
        ),
        "x86_64" => Dict(
            # Better be always explicit about `-march` & `-mtune`:
            # https://lemire.me/blog/2018/07/25/it-is-more-complicated-than-i-thought-mtune-march-in-gcc/
            "x86_64" => ["-march=x86-64", "-mtune=generic"],
            "avx"    => ["-march=sandybridge", "-mtune=sandybridge"],
            "avx2"   => ["-march=haswell", "-mtune=haswell"],
            "avx512" => ["-march=skylake-avx512", "-mtune=skylake-avx512"],
        ),
        "armv6l" => Dict(
            # This is the only known armv6l chip that runs Julia, so it's the only one we care about.
            "arm1176jzfs" => ["-mcpu=arm1176jzf-s", "-mfpu=vfp"],
        ),
        "armv7l" => Dict(
            # Base armv7l architecture, with the most basic of FPU's
            "armv7l"   => ["-march=armv7-a", "-mtune=generic-armv7-a", "-mfpu=vfpv3"],
            # armv7l plus NEON and vfpv4, (Raspberry Pi 2B+, RK3328, most boards Elliot has access to)
            "neonvfpv4" => ["-march=armv7-a", "-mtune=cortex-a53", "-mfpu=neon-vfpv4"],
        ),
        "aarch64" => Dict(
            # Base armv8.0-a architecture, tune for generic cortex-a57
            "armv8_0"  => ["-march=armv8-a", "-mtune=cortex-a57"],
        ),
        "powerpc64le" => Dict(
            "power8"  => ["-mcpu=power8", "-mtune=power8"],
            # Note that power9 requires GCC 6+, and we need CPUID for this
            #"power9"  => ["-mcpu=power9", "-mtune=power9"],
            # Eventually, we'll support power10, once we have compilers that support it.
            #"power10" => ["-mcpu=power10", "-mtune=power10"],
        )
    ),
    "gcc" => Dict(
        "aarch64" => Dict(
            # `clang`/`gcc` disagree on `rdm(a)`
            "armv8_1"            => ["-march=armv8-a+lse+crc+rdma", "-mtune=thunderx2t99"],
            # Note that these targets require gcc 9+
            "armv8_2_crypto"     => ["-march=armv8-a+lse+crc+rdma+aes+sha2", "-mtune=cortex-a76"],
            "armv8_4_crypto_sve" => ["-march=armv8-a+les+crc+rdma+aes+sha2+fp16fml+dotprod+sve", "-mtune=cortex-a76"]
        ),
    ),
    "clang" => Dict(
        "aarch64" => Dict(
            # `clang`/`gcc` disagree on `rdm` vs. `rdma`
            "armv8_1"            => ["-march=armv8-a+lse+crc+rdm", "-mtune=thunderx2t99"],
            # Note that these targets require clang 9+
            "armv8_2_crypto"     => ["-march=armv8-a+lse+crc+rdm+aes+sha2", "-mtune=cortex-a76"],
            "armv8_4_crypto_sve" => ["-march=armv8-a+les+crc+rdm+aes+sha2+fp16fml+dotprod+sve", "-mtune=cortex-a76"]
        ),
    ),
)
march(p::AbstractPlatform; default=nothing) = get(tags(p), "march", default)
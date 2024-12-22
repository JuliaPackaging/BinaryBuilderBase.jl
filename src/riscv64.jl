using Base: BinaryPlatforms

@static if !haskey(BinaryPlatforms.arch_mapping, "riscv64")

# We pirate a few functions and global variables from Base.BinaryPlatforms.
# These changes have been upstreamed to newer Julia versions, but we are stuck with Julia 1.7.
# This is not pretty. It seems to work.

function __init__()
    CPUID.ISAs_by_family["riscv64"] = [
        # We have no way to test riscv64 features yet, so we're only going to declare the lowest ISA:
        "riscv64" => CPUID.ISA(Set{UInt32}()),
    ]

    BinaryPlatforms.arch_mapping["riscv64"] = "(rv64|riscv64)"

    function get_set(arch, name)
        all = BinaryPlatforms.CPUID.ISAs_by_family[arch]
        return all[findfirst(x -> x.first == name, all)].second
    end
    BinaryPlatforms.arch_march_isa_mapping["riscv64"] = ["riscv64" => get_set("riscv64", "riscv64")]
end

function Base.BinaryPlatforms.validate_tags(tags::Dict)
    throw_invalid_key(k) = throw(ArgumentError("Key \"$(k)\" cannot have value \"$(tags[k])\""))
    # Validate `arch`
    if tags["arch"] ∉ ("x86_64", "i686", "armv7l", "armv6l", "aarch64", "powerpc64le", "riscv64")
        throw_invalid_key("arch")
    end
    # Validate `os`
    if tags["os"] ∉ ("linux", "macos", "freebsd", "windows")
        throw_invalid_key("os")
    end
    # Validate `os`/`arch` combination
    throw_os_mismatch() = throw(ArgumentError("Invalid os/arch combination: $(tags["os"])/$(tags["arch"])"))
    if tags["os"] == "windows" && tags["arch"] ∉ ("x86_64", "i686", "armv7l", "aarch64")
        throw_os_mismatch()
    end
    if tags["os"] == "macos" && tags["arch"] ∉ ("x86_64", "aarch64")
        throw_os_mismatch()
    end

    # Validate `os`/`libc` combination
    throw_libc_mismatch() = throw(ArgumentError("Invalid os/libc combination: $(tags["os"])/$(tags["libc"])"))
    if tags["os"] == "linux"
        # Linux always has a `libc` entry
        if tags["libc"] ∉ ("glibc", "musl")
            throw_libc_mismatch()
        end
    else
        # Nothing else is allowed to have a `libc` entry
        if haskey(tags, "libc")
            throw_libc_mismatch()
        end
    end

    # Validate `os`/`arch`/`call_abi` combination
    throw_call_abi_mismatch() = throw(ArgumentError("Invalid os/arch/call_abi combination: $(tags["os"])/$(tags["arch"])/$(tags["call_abi"])"))
    if tags["os"] == "linux" && tags["arch"] ∈ ("armv7l", "armv6l")
        # If an ARM linux has does not have `call_abi` set to something valid, be sad.
        if !haskey(tags, "call_abi") || tags["call_abi"] ∉ ("eabihf", "eabi")
            throw_call_abi_mismatch()
        end
    else
        # Nothing else should have a `call_abi`.
        if haskey(tags, "call_abi")
            throw_call_abi_mismatch()
        end
    end

    # Validate `libgfortran_version` is a parsable `VersionNumber`
    throw_version_number(k) = throw(ArgumentError("\"$(k)\" cannot have value \"$(tags[k])\", must be a valid VersionNumber"))
    if "libgfortran_version" in keys(tags) && tryparse(VersionNumber, tags["libgfortran_version"]) === nothing
        throw_version_number("libgfortran_version")
    end

    # Validate `cxxstring_abi` is one of the two valid options:
    if "cxxstring_abi" in keys(tags) && tags["cxxstring_abi"] ∉ ("cxx03", "cxx11")
        throw_invalid_key("cxxstring_abi")
    end

    # Validate `libstdcxx_version` is a parsable `VersionNumber`
    if "libstdcxx_version" in keys(tags) && tryparse(VersionNumber, tags["libstdcxx_version"]) === nothing
        throw_version_number("libstdcxx_version")
    end
end

end

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

#TODO using .BinaryPlatforms: arch_mapping, os_mapping, libc_mapping, call_abi_mapping,
#TODO     libgfortran_version_mapping, cxxstring_abi_mapping, libstdcxx_version_mapping
#TODO 
#TODO function Base.parse(::Type{Platform}, triplet::AbstractString; validate_strict::Bool = false)
#TODO     # Re-insert the architecture because the global assignments above don't stick
#TODO     CPUID.ISAs_by_family["riscv64"] = [
#TODO         # We have no way to test riscv64 features yet, so we're only going to declare the lowest ISA:
#TODO         "riscv64" => CPUID.ISA(Set{UInt32}()),
#TODO     ]
#TODO     BinaryPlatforms.arch_mapping["riscv64"] = "(rv64|riscv64)"
#TODO     BinaryPlatforms.arch_march_isa_mapping["riscv64"] = ["riscv64" => get_set("riscv64", "riscv64")]
#TODO 
#TODO     # Helper function to collapse dictionary of mappings down into a regex of
#TODO     # named capture groups joined by "|" operators
#TODO     c(mapping) = string("(",join(["(?<$k>$v)" for (k, v) in mapping], "|"), ")")
#TODO 
#TODO     # We're going to build a mondo regex here to parse everything:
#TODO     triplet_regex = Regex(string(
#TODO         "^",
#TODO         # First, the core triplet; arch/os/libc/call_abi
#TODO         c(arch_mapping),
#TODO         c(os_mapping),
#TODO         c(libc_mapping),
#TODO         c(call_abi_mapping),
#TODO         # Next, optional things, like libgfortran/libstdcxx/cxxstring abi
#TODO         c(libgfortran_version_mapping),
#TODO         c(cxxstring_abi_mapping),
#TODO         c(libstdcxx_version_mapping),
#TODO         # Finally, the catch-all for extended tags
#TODO         "(?<tags>(?:-[^-]+\\+[^-]+)*)?",
#TODO         "\$",
#TODO     ))
#TODO 
#TODO     m = match(triplet_regex, triplet)
#TODO     if m !== nothing
#TODO         # Helper function to find the single named field within the giant regex
#TODO         # that is not `nothing` for each mapping we give it.
#TODO         get_field(m, mapping) = begin
#TODO             for k in keys(mapping)
#TODO                 if m[k] !== nothing
#TODO                     # Convert our sentinel `nothing` values to actual `nothing`
#TODO                     if endswith(k, "_nothing")
#TODO                         return nothing
#TODO                     end
#TODO                     # Convert libgfortran/libstdcxx version numbers
#TODO                     if startswith(k, "libgfortran")
#TODO                         return VersionNumber(parse(Int,k[12:end]))
#TODO                     elseif startswith(k, "libstdcxx")
#TODO                         return VersionNumber(3, 4, parse(Int,m[k][11:end]))
#TODO                     else
#TODO                         return k
#TODO                     end
#TODO                 end
#TODO             end
#TODO         end
#TODO 
#TODO         # Extract the information we're interested in:
#TODO         arch = get_field(m, arch_mapping)
#TODO         os = get_field(m, os_mapping)
#TODO         libc = get_field(m, libc_mapping)
#TODO         call_abi = get_field(m, call_abi_mapping)
#TODO         libgfortran_version = get_field(m, libgfortran_version_mapping)
#TODO         libstdcxx_version = get_field(m, libstdcxx_version_mapping)
#TODO         cxxstring_abi = get_field(m, cxxstring_abi_mapping)
#TODO         function split_tags(tagstr)
#TODO             tag_fields = filter(!isempty, split(tagstr, "-"))
#TODO             if isempty(tag_fields)
#TODO                 return Pair{String,String}[]
#TODO             end
#TODO             return map(v -> Symbol(v[1]) => v[2], split.(tag_fields, "+"))
#TODO         end
#TODO         tags = split_tags(m["tags"])
#TODO 
#TODO         # Special parsing of os version number, if any exists
#TODO         function extract_os_version(os_name, pattern)
#TODO             m_osvn = match(pattern, m[os_name])
#TODO             if m_osvn !== nothing
#TODO                 return VersionNumber(m_osvn.captures[1])
#TODO             end
#TODO             return nothing
#TODO         end
#TODO         os_version = nothing
#TODO         if os == "macos"
#TODO             os_version = extract_os_version("macos", r".*darwin([\d\.]+)")
#TODO         end
#TODO         if os == "freebsd"
#TODO             os_version = extract_os_version("freebsd", r".*freebsd([\d.]+)")
#TODO         end
#TODO 
#TODO         return Platform(
#TODO             arch, os;
#TODO             validate_strict,
#TODO             libc,
#TODO             call_abi,
#TODO             libgfortran_version,
#TODO             cxxstring_abi,
#TODO             libstdcxx_version,
#TODO             os_version,
#TODO             tags...,
#TODO         )
#TODO     end
#TODO     throw(ArgumentError("Platform `$(triplet)` is not an officially supported platform"))
#TODO end

end

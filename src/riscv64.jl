using Base: BinaryPlatforms

@static if !haskey(BinaryPlatforms.arch_mapping, "riscv64")

# We pirate a few functions and global variables from Base.BinaryPlatforms.
# These changes have been upstreamed to newer Julia versions, but we are stuck with Julia 1.7.
# This is not pretty. It seems to work.

function setup_riscv64()
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

__init__() = setup_riscv64()



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

function Base.parse(::Type{Platform}, triplet::AbstractString; validate_strict::Bool = false)
    # setup_riscv64()

    arch_mapping = BinaryPlatforms.arch_mapping
    os_mapping = BinaryPlatforms.os_mapping
    libc_mapping = BinaryPlatforms.libc_mapping
    call_abi_mapping = BinaryPlatforms.call_abi_mapping
    libgfortran_version_mapping = BinaryPlatforms.libgfortran_version_mapping
    cxxstring_abi_mapping = BinaryPlatforms.cxxstring_abi_mapping
    libstdcxx_version_mapping = BinaryPlatforms.libstdcxx_version_mapping

    # Helper function to collapse dictionary of mappings down into a regex of
    # named capture groups joined by "|" operators
    c(mapping) = string("(",join(["(?<$k>$v)" for (k, v) in mapping], "|"), ")")

    # We're going to build a mondo regex here to parse everything:
    triplet_regex = Regex(string(
        "^",
        # First, the core triplet; arch/os/libc/call_abi
        c(arch_mapping),
        c(os_mapping),
        c(libc_mapping),
        c(call_abi_mapping),
        # Next, optional things, like libgfortran/libstdcxx/cxxstring abi
        c(libgfortran_version_mapping),
        c(cxxstring_abi_mapping),
        c(libstdcxx_version_mapping),
        # Finally, the catch-all for extended tags
        "(?<tags>(?:-[^-]+\\+[^-]+)*)?",
        "\$",
    ))

    m = match(triplet_regex, triplet)
    if m !== nothing
        # Helper function to find the single named field within the giant regex
        # that is not `nothing` for each mapping we give it.
        get_field(m, mapping) = begin
            for k in keys(mapping)
                if m[k] !== nothing
                    # Convert our sentinel `nothing` values to actual `nothing`
                    if endswith(k, "_nothing")
                        return nothing
                    end
                    # Convert libgfortran/libstdcxx version numbers
                    if startswith(k, "libgfortran")
                        return VersionNumber(parse(Int,k[12:end]))
                    elseif startswith(k, "libstdcxx")
                        return VersionNumber(3, 4, parse(Int,m[k][11:end]))
                    else
                        return k
                    end
                end
            end
        end

        # Extract the information we're interested in:
        arch = get_field(m, arch_mapping)
        os = get_field(m, os_mapping)
        libc = get_field(m, libc_mapping)
        call_abi = get_field(m, call_abi_mapping)
        libgfortran_version = get_field(m, libgfortran_version_mapping)
        libstdcxx_version = get_field(m, libstdcxx_version_mapping)
        cxxstring_abi = get_field(m, cxxstring_abi_mapping)
        function split_tags(tagstr)
            tag_fields = filter(!isempty, split(tagstr, "-"))
            if isempty(tag_fields)
                return Pair{String,String}[]
            end
            return map(v -> Symbol(v[1]) => v[2], split.(tag_fields, "+"))
        end
        tags = split_tags(m["tags"])

        # Special parsing of os version number, if any exists
        function extract_os_version(os_name, pattern)
            m_osvn = match(pattern, m[os_name])
            if m_osvn !== nothing
                return VersionNumber(m_osvn.captures[1])
            end
            return nothing
        end
        os_version = nothing
        if os == "macos"
            os_version = extract_os_version("macos", r".*darwin([\d\.]+)")
        end
        if os == "freebsd"
            os_version = extract_os_version("freebsd", r".*freebsd([\d.]+)")
        end

        return Platform(
            arch, os;
            validate_strict,
            libc,
            call_abi,
            libgfortran_version,
            cxxstring_abi,
            libstdcxx_version,
            os_version,
            tags...,
        )
    end
    throw(ArgumentError("Platform `$(triplet)` is not an officially supported platform"))
end

end

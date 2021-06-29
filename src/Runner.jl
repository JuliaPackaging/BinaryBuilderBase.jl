import Base: strip
abstract type Runner; end

export default_host_platform

# Host platform _must_ match the C++ string ABI of the binaries we get from the
# repositories.  Note: when preferred_gcc_version=v"4" we can't really build for
# that C++ string ABI :-(
"""
    default_host_platform

The default host platform in the build environment.
"""
const default_host_platform = Platform("x86_64", "linux"; libc="musl", cxxstring_abi="cxx11")

function nbits(p::AbstractPlatform)
    if arch(p) in ("i686", "armv6l", "armv7l")
        return 32
    elseif arch(p) in ("x86_64", "aarch64", "powerpc64le")
        return 64
    else
        error("Unknown bitwidth for architecture $(arch(p))")
    end
end

function proc_family(p::AbstractPlatform)
    if arch(p) in ("x86_64", "i686")
        return "intel"
    elseif arch(p) in ("armv6l", "armv7l", "aarch64")
        return "arm"
    elseif arch(p) == "powerpc64le"
        return "power"
    else
        error("Unknown processor family for architecture $(arch(p))")
    end
end

# Convert platform to a triplet, but strip out the ABI parts.
# Also translate `armvXl` -> `arm` for now, since that's what most
# compiler toolchains call it.  :(
function aatriplet(p::AbstractPlatform)
    t = triplet(abi_agnostic(p))
    t = replace(t, "armv7l" => "arm")
    t = replace(t, "armv6l" => "arm")
    return t
end
# XXX: we want AnyPlatform to look like `x86_64-linux-musl` in the build environment.
aatriplet(p::AnyPlatform) = aatriplet(default_host_platform)

"""
    generate_compiler_wrappers!(platform::AbstractPlatform; bin_path::AbstractString,
                                host_platform::AbstractPlatform = $(repr(default_host_platform)),
                                compilers::Vector{Symbol} = [:c],
                                allow_unsafe_flags::Bool = false,
                                lock_microarchitecture::Bool = true)

We generate a set of compiler wrapper scripts within our build environment to force all
build systems to honor the necessary sets of compiler flags to build for our systems.
Note that while `platform_envs()` sets many environment variables, those values are
intended to be optional/overridable.  These values, while still overridable by directly
invoking a compiler binary directly (e.g. /opt/{target}/bin/{target}-gcc), are much more
difficult to override, as the flags embedded in these wrappers are absolutely necessary,
and even simple programs will not compile without them.
"""
function generate_compiler_wrappers!(platform::AbstractPlatform; bin_path::AbstractString,
                                     host_platform::AbstractPlatform = default_host_platform,
                                     compilers::Vector{Symbol} = [:c],
                                     allow_unsafe_flags::Bool = false,
                                     lock_microarchitecture::Bool = true,
                                     bootstrap::Bool = !isempty(bootstrap_list),
                                     )
    # Wipe that directory out, in case it already had compiler wrappers
    rm(bin_path; recursive=true, force=true)
    mkpath(bin_path)

    # Early-exit if we're bootstrapping
    if bootstrap
        return
    end

    target = aatriplet(platform)
    host_target = aatriplet(host_platform)

    function wrapper(io::IO,
                     prog::String;
                     # Flags that are always prepended
                     flags::Vector{String} = String[],
                     # Flags that are prepended if we think we're compiling (e.g. no `-x assembler`)
                     compile_only_flags::Vector = String[],
                     # Flags that are postpended if we think we're linking (e.g. no `-c`)
                     link_only_flags::Vector = String[],
                     allow_ccache::Bool = true,
                     no_soft_float::Bool = false,
                     hash_args::Bool = false,
                     extra_cmds::String = "",
                     env::Dict{String,String} = Dict{String,String}(),
                     unsafe_flags = String[])
        write(io, """
        #!/bin/bash
        # This compiler wrapper script brought into existence by `generate_compiler_wrappers!()`

        if [ "x\${SUPER_VERBOSE}" = "x" ]; then
            vrun() { "\$@"; }
        else
            vrun() { echo -e "\\e[96m\$@\\e[0m" >&2; "\$@"; }
        fi

        ARGS=( "\$@" )
        PRE_FLAGS=()
        POST_FLAGS=()
        """)

        # Sometimes we need to look at the hash of our arguments
        if hash_args
            write(io, """
            ARGS_HASH="\$(echo -n "\$*" | sha1sum | cut -c1-8)"
            """)
        end

        # If we're given always-prepend flags, include them
        if !isempty(flags)
            println(io)
            for cf in flags
                println(io, "PRE_FLAGS+=( $cf )")
            end
            println(io)
        end

        # If we're given compile-only flags, include them only if `-x assembler` is not provided
        if !isempty(compile_only_flags)
            println(io)
            println(io, "if [[ \" \${ARGS[@]} \" != *' -x assembler '* ]]; then")
            for cf in compile_only_flags
                println(io, "    PRE_FLAGS+=( $cf )")
            end
            println(io, "fi")
            println(io)
        end

        # If we're given link-only flags, include them only if `-c` or other link-disablers are not provided.
        if !isempty(link_only_flags)
            println(io)
            println(io, "if [[ \" \${ARGS[@]} \" != *' -c '* ]] && [[ \" \${ARGS[@]} \" != *' -E '* ]] && [[ \" \${ARGS[@]} \" != *' -M '* ]] && [[ \" \${ARGS[@]} \" != *' -fsyntax-only '* ]]; then")
            for lf in link_only_flags
                println(io, "    POST_FLAGS+=( $lf )")
            end
            println(io, "fi")
            println(io)
        end

        # Insert extra commands from the user (usually some kind of conditional setting
        # of PRE_FLAGS and POST_FLAGS)
        println(io)
        write(io, extra_cmds)
        println(io)

        for (name, val) in env
            write(io, "export $(name)=\"$(val)\"\n")
        end

        # TODO: improve this check
        if lock_microarchitecture
            write(io, raw"""
                      if [[ " ${ARGS[@]} " == *"-march="* ]]; then
                          echo "Cannot force an architecture" >&2
                          exit 1
                      fi
                      """)
            println(io)
        end

        if no_soft_float
            write(io, raw"""
                      if [[ " ${ARGS[@]} " == *"-mfloat-abi=soft"* ]]; then
                          echo "${target} platform does not support soft-float ABI" >&2
                          exit 1
                      fi
                      """)
            println(io)
        end

        if length(unsafe_flags) >= 1
            write(io, """
            if [[ "\${ARGS[@]}" =~ \"$(join(unsafe_flags, "\"|\""))\" ]]; then
                echo -e \"You used one or more of the unsafe flags: $(join(unsafe_flags, ", "))\\nPlease repent.\" >&2
                exit 1
            fi
            """)
            println(io)
        end

        if allow_ccache
            write(io, """
            if [ \${USE_CCACHE} == "true" ]; then
                CCACHE="ccache"
            fi
            """)
        end
        write(io, """
        vrun \${CCACHE} $(prog) "\${PRE_FLAGS[@]}" "\${ARGS[@]}" "\${POST_FLAGS[@]}"
        """)
    end

    # Helper invocations
    target_tool(io::IO, tool::String, args...; kwargs...) = wrapper(io, "/opt/$(target)/bin/$(target)-$(tool)", args...; kwargs...)
    llvm_tool(io::IO, tool::String, args...; kwargs...) = wrapper(io, "/opt/$(host_target)/bin/llvm-$(tool)", args...; kwargs...)

    # For now this is required for Clang, since apple spells aarch64 as "arm64".
    # Should probably be fixed upstream, but will do for now
    clang_target_triplet(p::AbstractPlatform) = replace(aatriplet(p), "aarch64" => "arm64")

    function clang_flags!(p::AbstractPlatform, flags::Vector{String} = String[])
        # Focus the clang targeting laser
        append!(flags, [
            # Set the `target` for `clang` so it generates the right kind of code
            "-target $(clang_target_triplet(p))",
            # Set our sysroot to the platform-specific location, dropping compiler ABI annotations
            "--sysroot=/opt/$(aatriplet(p))/$(aatriplet(p))/sys-root",
        ])
        # For MacOS and FreeBSD, we don't set `-rtlib`, and FreeBSD is special-cased within the LLVM source tree
        # to not allow for -gcc-toolchain, which means that we have to manually add the location of libgcc_s.  LE SIGH.
        # We do that within `clang_linker_flags()`, so that we don't get "unused argument" warnings all over the place.
        # https://github.com/llvm-mirror/clang/blob/f3b7928366f63b51ffc97e74f8afcff497c57e8d/lib/Driver/ToolChains/FreeBSD.cpp
        # For everything else, we provide `-rtlib=libgcc` because clang-builtins are broken (pending Valentin-based-magic),
        # and we also need to provide `-stdlib=libstdc++` to match Julia on these platforms.
        if !Sys.isbsd(p)
            append!(flags, [
                # Find GCC toolchain here (for things like libgcc_s)
                "--gcc-toolchain=/opt/$(aatriplet(p))"
                # Use libgcc as the C runtime library
                "-rtlib=libgcc"
                # Use libstdc++ as the C++ runtime library
                "-stdlib=libstdc++"
            ])
        end
        return flags
    end

    function macos_version(kernel_version::Integer)
        kernel_to_macos = Dict(
            12 => "10.8",
            13 => "10.9",
            14 => "10.10",
            15 => "10.11",
            16 => "10.12",
            17 => "10.13",
            18 => "10.14",
            19 => "10.15",
            20 => "11.0",
        )
        return get(kernel_to_macos, kernel_version, nothing)
    end
    function macos_version(p::AbstractPlatform)
        if os(p) != "macos"
            return nothing
        end

        # If no `os_version` is specified in `p`, default to the oldest we support in the Julia world,
        # which is `10.8`, but if it is actually specified, then set that corresponding value.
        #version = something(os_version(p), v"14.0.0")

        # Eventually, we'll take this in `os_version(p)`, but not just yet.  We need to fix the paths
        # to the compiler shards first, since right now they have `14` at the end
        version = v"14.0.0"
        return macos_version(version.major)
    end

    function min_macos_version_flag(p::AbstractPlatform)
        # Ask compilers to compile for a minimum macOS version
        return "-mmacosx-version-min=$(macos_version(p))"
    end

    function clang_compile_flags!(p::AbstractPlatform, flags::Vector{String} = String[])
        if lock_microarchitecture
            append!(flags, get_march_flags(arch(p), march(p), "clang"))
        end
        if Sys.isapple(p)
            append!(flags, String[
                # On MacOS, we need to override the typical C++ include search paths, because it always includes
                # the toolchain C++ headers first.  Valentin tracked this down to:
                # https://github.com/llvm/llvm-project/blob/0378f3a90341d990236c44f297b923a32b35fab1/clang/lib/Driver/ToolChains/Darwin.cpp#L1944-L1978
                "-nostdinc++",
                "-isystem",
                "/opt/$(aatriplet(p))/$(aatriplet(p))/sys-root/usr/include/c++/v1",
                # We also add `-Wno-unused-command-line-argument` so that if someone does something like
                # `clang -Werror -o foo a.o b.o`, it doesn't complain due to the fact that that is using
                # `clang` as a linker (and we have no real way to detect that in the wrapper), which will
                # cause `clang` to complain about compiler flags being passed in.
                "-Wno-unused-command-line-argument",
                min_macos_version_flag(p),
            ])
        end
        return flags
    end

    function clang_link_flags!(p::AbstractPlatform, flags::Vector{String} = String[])
        # On macos and freebsd, we must pass in the `/lib` directory for some reason
        if Sys.isbsd(p)
            push!(flags, "-L/opt/$(aatriplet(p))/$(aatriplet(p))/lib")
        end

        # we want to use a particular linker with clang.  But we want to avoid warnings about unused
        # flags when just compiling, so we put it into "linker-only flags".
        push!(flags, "-fuse-ld=$(aatriplet(p))")

        # On macos, we need to pass `-headerpad_max_install_names` so that we have lots of space
        # for `install_name_tool` shenanigans during audit fixups.
        if Sys.isapple(p)
            push!(flags, "-headerpad_max_install_names")
        end
        return flags
    end


    function macos_gcc_flags!(p::AbstractPlatform, flags::Vector{String} = String[])
        # On macOS, if we're on an old GCC, the default -syslibroot that gets
        # passed to the linker isn't calculated correctly, so we have to manually set it.
        gcc_version, llvm_version = select_compiler_versions(p)
        if gcc_version.major in (4, 5)
            push!(flags, "-Wl,-syslibroot,/opt/$(aatriplet(p))/$(aatriplet(p))/sys-root")
        end
        push!(flags, min_macos_version_flag(p))
        return flags
    end

    function gcc_flags!(p::AbstractPlatform, flags::Vector{String} = String[])
        # Force proper cxx11 string ABI usage w00t w00t!
        if cxxstring_abi(p) == "cxx11"
            push!(flags, "-D_GLIBCXX_USE_CXX11_ABI=1")
        elseif cxxstring_abi(p) == "cxx03"
            push!(flags, "-D_GLIBCXX_USE_CXX11_ABI=0")
        end

        # Simulate some of the `__OSX_AVAILABLE()` macro usage that is broken in GCC
        # Currently, we only target 10.10, but eventually, we'll want to tailor this to `os_version(p)`
        if Sys.isapple(p) && 14 < 16
            # Disable usage of `clock_gettime()`
            push!(flags, "-D_DARWIN_FEATURE_CLOCK_GETTIME=0")
        end

        # Use hash of arguments to provide consistent, unique random seed
        push!(flags, "-frandom-seed=0x\${ARGS_HASH}")

        if Sys.isapple(p)
            macos_gcc_flags!(p, flags)
        end
        return flags
    end

    function gcc_compile_flags!(p::AbstractPlatform, flags::Vector{String} = String[])
        if lock_microarchitecture
            append!(flags, get_march_flags(arch(p), march(p), "gcc"))
        end
        return flags
    end

    function gcc_link_flags!(p::AbstractPlatform, flags::Vector{String} = String[])
        # Yes, it does seem that the inclusion of `/lib64` on `powerpc64le` was fixed
        # in GCC 6, broken again in GCC 7, and then fixed again for GCC 8 and 9
        gcc_version, llvm_version = select_compiler_versions(p)
        if arch(p) == "powerpc64le" && Sys.islinux(p) && gcc_version.major in (4, 5, 7)
            append!(flags, String[
                "-L/opt/$(aatriplet(p))/$(aatriplet(p))/sys-root/lib64",
                "-Wl,-rpath-link,/opt/$(aatriplet(p))/$(aatriplet(p))/sys-root/lib64",
            ])
        elseif Sys.isapple(p)
            push!(flags, "-headerpad_max_install_names")
        end
        return flags
    end

    function gcc_unsafe_flags!(p::AbstractPlatform, flags::Vector{String} = String[])
        if !allow_unsafe_flags
            return String["-Ofast", "-ffast-math", "-funsafe-math-optimizations"]
        end
        return String[]
    end

    function gcc_wrapper(io::IO, tool::String, p::AbstractPlatform, allow_ccache::Bool = true)
        return wrapper(io,
            "/opt/$(aatriplet(p))/bin/$(aatriplet(p))-$(tool)";
            flags=gcc_flags!(p),
            compile_only_flags=gcc_compile_flags!(p),
            link_only_flags=gcc_link_flags!(p),
            unsafe_flags=gcc_unsafe_flags!(p),
            hash_args = true,
            allow_ccache,
            no_soft_float=arch(p) in ("armv6l", "armv7l"),
        )
    end

    function clang_wrapper(io::IO, tool::String, p::AbstractPlatform)
        flags = clang_flags!(p)
        return wrapper(io,
            "/opt/$(host_target)/bin/$(tool)";
            flags=flags,
            compile_only_flags=clang_compile_flags!(p),
            link_only_flags=clang_link_flags!(p),
            no_soft_float=arch(p) in ("armv6l", "armv7l"),
        )
    end

    # C/C++/Fortran
    gcc(io::IO, p::AbstractPlatform)      = gcc_wrapper(io, "gcc", p)
    gxx(io::IO, p::AbstractPlatform)      = gcc_wrapper(io, "g++", p)
    gfortran(io::IO, p::AbstractPlatform) = gcc_wrapper(io, "gfortran", p, false)

    clang(io::IO, p::AbstractPlatform)    = clang_wrapper(io, "clang", p)
    clangxx(io::IO, p::AbstractPlatform)  = clang_wrapper(io, "clang++", p)

    # Our general `cc`  points to `gcc` for most systems, but `clang` for MacOS and FreeBSD
    function cc(io::IO, p::AbstractPlatform)
        if Sys.isbsd(p)
            return clang(io, p)
        else
            return gcc(io, p)
        end
    end
    function cxx(io::IO, p::AbstractPlatform)
        if Sys.isbsd(p)
            return clangxx(io, p)
        else
            return gxx(io, p)
        end
    end
    fc(io::IO, p::AbstractPlatform) = gfortran(io, p)

    # Go stuff where we build an environment mapping each time we invoke `go-${target}`
    function GOOS(p::AbstractPlatform)
        if os(p) == "macos"
            return "darwin"
        end
        return os(p)
    end
    function GOARCH(p::AbstractPlatform)
        arch_mapping = Dict(
            "armv6l" => "arm",
            "armv7l" => "arm",
            "aarch64" => "arm64",
            "x86_64" => "amd64",
            "i686" => "386",
            "powerpc64le" => "ppc64le",
        )
        return arch_mapping[arch(p)]
    end
    function go(io::IO, p::AbstractPlatform)
        env = Dict(
            "GOOS" => GOOS(p),
            "GOROOT" => "/opt/$(host_target)/go",
            "GOARCH" => GOARCH(p),
        )
        return wrapper(io, "/opt/$(host_target)/go/bin/go"; env=env, allow_ccache=false)
    end
    gofmt(io::IO, p::AbstractPlatform) = wrapper(io, "/opt/$(host_target)/go/bin/gofmt"; allow_ccache=false)

    # Rust stuff
    function rust_flags!(p::AbstractPlatform, flags::Vector{String} = String[])
        if Sys.islinux(p)
            push!(flags, "-Clinker=$(aatriplet(p))-gcc")

            # Add aarch64 workaround https://github.com/rust-lang/rust/issues/46651#issuecomment-402850885
            if arch(p) == "aarch64" && libc(p) == "musl"
                push!(flags, "-C link-arg=-lgcc")
            end
        elseif Sys.iswindows(p)
            # Rust on i686 mingw32 can't deal with exceptions
            # https://github.com/rust-lang/rust/issues/12859
            if arch(p) == "i686"
                push!(flags, "-C panic=abort")
            end
        end
        return flags
    end
    function rustc(io::IO, p::AbstractPlatform)
        extra_cmds = """
        if [[ " \${ARGS[@]} " == *'--target'* ]]; then
            if ! [[ " \${ARGS[@]} " =~ --target(=| )$(map_rust_target(p)) ]]; then
                echo "Attempting to invoke targeted 'rustc' wrapper with a different target! (Expected $(map_rust_target(p)))" >&2
                echo "args: \${ARGS[@]}" >&2
                exit 1
            fi
        else
            PRE_FLAGS+=( '--target=$(map_rust_target(p))' )
        fi
        """
        wrapper(io, "/opt/$(host_target)/bin/rustc"; flags=rust_flags!(p), allow_ccache=false, extra_cmds=extra_cmds)
    end
    rustup(io::IO, p::AbstractPlatform) = wrapper(io, "/opt/$(host_target)/bin/rustup"; allow_ccache=false)
    cargo(io::IO, p::AbstractPlatform) = wrapper(io, "/opt/$(host_target)/bin/cargo"; allow_ccache=false)

    # Meson REQUIRES that `CC`, `CXX`, etc.. are set to the host utils.  womp womp.
    function meson(io::IO, p::AbstractPlatform)
        meson_env = Dict(
            "AR"     => "$(host_target)-ar",
            "CC"     => "$(host_target)-cc",
            "CXX"    => "$(host_target)-c++",
            "FC"     => "$(host_target)-f77",
            "LD"     => "$(host_target)-ld",
            "NM"     => "$(host_target)-nm",
            "OBJC"   => "$(host_target)-cc",
            "RANLIB" => "$(host_target)-ranlib",
        )
        wrapper(io, "/usr/bin/meson"; allow_ccache=false, env=meson_env)
    end

    # Patchelf needs some page-alignment on aarch64 and ppc64le forced into its noggin
    # https://github.com/JuliaPackaging/BinaryBuilder.jl/commit/cce4f8fdbb16425d245ab87a50f60d1a16d04948
    function patchelf(io::IO, p::AbstractPlatform)
        extra_cmds = ""
        if Sys.islinux(p) && arch(p) in ("aarch64", "powerpc64le")
            extra_cmds = raw"""
            if [[ " ${ARGS[@]} " != *'--page-size'* ]]; then
                PRE_FLAGS+=( '--page-size' '65536' )
            fi
            """
        end
        wrapper(io, "/usr/bin/patchelf"; allow_ccache=false, extra_cmds=extra_cmds)
    end

    # We pass `-D` to all `ar` invocations (unless `-U` is explicitly passed) for reproducibility
    function ar(io::IO, p::AbstractPlatform)
        ar_name = string(aatriplet(p), "-ar")
        if Sys.isapple(p)
            ar_name = "llvm-ar"
        end
        extra_cmds = raw"""
        if [[ " ${ARGS[0]} " =~ --* ]]; then
            # do nothing, it's probably --version or something
            true
        elif [[ " ${ARGS[0]} " != *'U'* ]]; then
            # Eliminate the `u` option, as it's incompatible with `D` and is just an optimization
            if [[ " ${ARGS[0]} " == *'u'* ]]; then
                ARGS[0]=$(echo "${ARGS[0]}" | tr -d u)
            fi

            # Add -D for "Deterministic mode"
            ARGS[0]="${ARGS[0]}D"
        else
            echo "Non-reproducibility alert: This 'ar' invocation uses the '-U' flag which embeds timestamps." >&2
            echo "ar flags: ${ARGS[@]}" >&2
            echo "Continuing build, but please repent." >&2
        fi
        """
        wrapper(io, string("/opt/", aatriplet(p), "/bin/", ar_name); allow_ccache=false, extra_cmds=extra_cmds)
    end

    function ranlib(io::IO, p::AbstractPlatform)
        if !Sys.isapple(p)
            ranlib_name = string(aatriplet(p), "-ranlib")
            extra_cmds = raw"""
            if [[ " ${ARGS[@]} " =~ "-[hHvVt]*U" ]]; then
                echo "Non-reproducibility alert: This `ranlib` invocation uses the `-U` flag which embeds timestamps." >&2
                echo "ranlib flags: ${ARGS[@]}" >&2
                echo "Continuing build, but please repent." >&2
            else
                PRE_FLAGS+=( '-D' )
            fi
            """
        else
            # llvm-ranlib is always reproducible
            ranlib_name = "llvm-ranlib"
            extra_cmds = ""
        end
        wrapper(io, string("/opt/", aatriplet(p), "/bin/", ranlib_name); allow_ccache=false, extra_cmds=extra_cmds)
    end

    function dlltool(io::IO, p::AbstractPlatform)
        extra_cmds = raw"""
        PRE_FLAGS+=( --temp-prefix /tmp/dlltool-${ARGS_HASH} )
        """
        wrapper(io, string("/opt/", aatriplet(p), "/bin/", string(aatriplet(p), "-dlltool")); allow_ccache=false, extra_cmds=extra_cmds, hash_args=true)
    end

    # Write out a bunch of common tools
    for tool in (:as, :cpp, :ld, :nm, :libtool, :objcopy, :objdump, :otool,
                 :strip, :install_name_tool, :dlltool, :windres, :winmc, :lipo)
        @eval $(tool)(io::IO, p::AbstractPlatform) = $(wrapper)(io, string("/opt/", aatriplet(p), "/bin/", aatriplet(p), "-", $(string(tool))); allow_ccache=false)
    end

    # c++filt is hard to write in symbols
    function cxxfilt(io::IO, p::AbstractPlatform)
        if Sys.isapple(p)
            # We must use `llvm-cxxfilt` on MacOS
            path = "/opt/$(aatriplet(p))/bin/llvm-cxxfilt"
        else
            path = "/opt/$(aatriplet(p))/bin/$(aatriplet(p))-c++filt"
        end
        return wrapper(io, path; allow_ccache=false)
    end

    function dsymutil(io::IO, p::AbstractPlatform)
        if !Sys.isapple(p)
            # Nobody except macOS has a `dsymutil`
            return (io, p) -> nothing
        end

        return wrapper(io, "/opt/$(aatriplet(p))/bin/dsymutil"; allow_ccache=false)
    end

    function readelf(io::IO, p::AbstractPlatform)
        if Sys.isapple(p)
            # macOS doesn't have a readelf
            return (io, p) -> nothing
        end
        return wrapper(io, "/opt/$(aatriplet(p))/bin/$(aatriplet(p))-readelf"; allow_ccache=false)
    end

    function write_wrapper(wrappergen, p, fname)
        file_path = joinpath(bin_path, triplet(p), fname)
        mkpath(dirname(file_path))
        open(io -> Base.invokelatest(wrappergen, io, p), file_path, "w")
        chmod(file_path, 0o775)
    end

    ## Generate compiler wrappers for both our host and our target.
    for p in unique((host_platform, platform))
        t = aatriplet(p)

        # Generate `:c` compilers
        if :c in compilers
            write_wrapper(cc, p, "$(t)-cc")
            write_wrapper(cxx, p, "$(t)-c++")

            # Generate `gcc`, `g++`, `clang` and `clang++`
            write_wrapper(gcc, p, "$(t)-gcc")
            write_wrapper(gxx, p, "$(t)-g++")
            write_wrapper(clang, p, "$(t)-clang")
            write_wrapper(clangxx, p, "$(t)-clang++")

            # Someday, you will be split out
            write_wrapper(gfortran, p, "$(t)-f77")
            write_wrapper(gfortran, p, "$(t)-gfortran")
        end


        # Binutils (we always do these)
        write_wrapper(ar, p, "$(t)-ar")
        write_wrapper(as, p, "$(t)-as")
        write_wrapper(cpp, p, "$(t)-cpp")
        write_wrapper(cxxfilt, p, "$(t)-c++filt")
        write_wrapper(ld, p, "$(t)-ld")
        # ld wrappers for clang's `-fuse-ld=$(target)`
        if Sys.isapple(p)
            write_wrapper(ld, p, "ld64.$(t)")
        else
            write_wrapper(ld, p, "ld.$(t)")
        end
        write_wrapper(nm, p, "$(t)-nm")
        write_wrapper(libtool, p, "$(t)-libtool")
        write_wrapper(objcopy, p, "$(t)-objcopy")
        write_wrapper(objdump, p, "$(t)-objdump")
        write_wrapper(ranlib, p, "$(t)-ranlib")
        write_wrapper(readelf, p, "$(t)-readelf")
        write_wrapper(strip, p, "$(t)-strip")

        # Special mac stuff
        if Sys.isapple(p)
            write_wrapper(install_name_tool, p, "$(t)-install_name_tool")
            write_wrapper(lipo, p, "$(t)-lipo")
            write_wrapper(dsymutil, p, "$(t)-dsymutil")
            write_wrapper(otool, p, "$(t)-otool")
        end

        # Special Windows stuff
        if Sys.iswindows(p)
            write_wrapper(dlltool, p, "$(t)-dlltool")
            write_wrapper(windres, p, "$(t)-windres")
            write_wrapper(winmc, p, "$(t)-winmc")
        end

        # Generate go stuff
        if :go in compilers
            write_wrapper(go, p, "$(t)-go")
            write_wrapper(gofmt, p, "$(t)-gofmt")
        end

        # Misc. utilities
        write_wrapper(patchelf, p, "$(t)-patchelf")
    end

    # Rust stuff doesn't use the normal "host" platform, it uses x86_64-linux-gnu, so we always have THREE around,
    # because clever build systems like `meson` ask Rust what its native system is, and it truthfully answers
    # `x86_64-linux-gnu`, while other build systems might say `x86_64-linux-musl` with no less accuracy.  So for
    # safety, we just ship all three all the time.
    if :rust in compilers
        for p in unique((platform, host_platform))
            t = aatriplet(p)
            write_wrapper(rustc, p, "$(t)-rustc")
            write_wrapper(rustup, p, "$(t)-rustup")
            write_wrapper(cargo, p, "$(t)-cargo")

            # For FreeBSD and macOS we need to create an unversioned link for
            # gcc because that's the linker our Rust toolchain expects:
            # https://github.com/JuliaPackaging/Yggdrasil/blob/fff0583bc2d8f32e450c427684f295524f38535d/0_RootFS/Rust/build_tarballs.jl#L115-L126.
            if Sys.isbsd(p) && os_version(p) !== nothing
                tmp_p = deepcopy(p)
                delete!(tags(tmp_p), "os_version")
                symlink("$(t)-gcc", joinpath(bin_path, triplet(p), "$(aatriplet(tmp_p))-gcc"))
            end
            # Currently our Rust toolchain expects the linker for armv7l and
            # armv6l with the platform "*l" suffix in the platform.  Until
            # https://github.com/JuliaPackaging/Yggdrasil/pull/2168 makes it to
            # the Rust toolchain, we create a symlink to work around this issue.
            if proc_family(p) == "arm" && nbits(p) == 32
                symlink("$(t)-gcc", joinpath(bin_path, triplet(p), "$(triplet(abi_agnostic(p)))-gcc"))
            end
        end
    end

    # Write a single wrapper for `meson`
    write_wrapper(meson, host_platform, "meson")

    default_tools = [
        # Binutils
        "ar", "as", "c++filt", "ld", "nm", "libtool", "objcopy", "ranlib", "readelf", "strip",

        # Misc. utilities
        "patchelf",
    ]

    if Sys.isapple(platform)
        append!(default_tools, ("dsymutil", "lipo", "otool", "install_name_tool"))
    elseif Sys.iswindows(platform)
        append!(default_tools, ("dlltool", "windres", "winmc"))
    end

    if :c in compilers
        append!(default_tools, ("cc", "c++", "cpp", "f77", "gfortran", "gcc", "clang", "g++", "clang++"))
    end
    if :rust in compilers
        append!(default_tools, ("rustc","rustup","cargo"))
    end
    if :go in compilers
        append!(default_tools, ("go", "gofmt"))
    end
    # Create symlinks for default compiler invocations, invoke target toolchain
    for tool in default_tools
        symlink("$(target)-$(tool)", joinpath(bin_path, triplet(platform), tool))
    end
end

# Translation mappers for our target names to cargo-compatible ones
map_rust_arch(p::AbstractPlatform) = replace(arch(p), "armv7l" => "armv7")
function map_rust_target(p::AbstractPlatform)
    if Sys.isapple(p)
        return "$(map_rust_arch(p))-apple-darwin"
    elseif Sys.isfreebsd(p)
        return "$(map_rust_arch(p))-unknown-freebsd"
    elseif Sys.iswindows(p)
        return "$(map_rust_arch(p))-pc-windows-gnu"
    else
        libc_str = libc(p) == "glibc" ? "gnu" : libc(p)
        call_abi_str = something(call_abi(p), "")
        return "$(map_rust_arch(p))-unknown-linux-$(libc_str)$(call_abi_str)"
    end
end

"""
    platform_envs(platform::AbstractPlatform)

Given a `platform`, generate a `Dict` mapping representing all the environment
variables to be set within the build environment to force compiles toward the
defined target architecture.  Examples of things set are `PATH`, `CC`,
`RANLIB`, as well as nonstandard things like `target`.
"""
function platform_envs(platform::AbstractPlatform, src_name::AbstractString;
                       host_platform = default_host_platform,
                       bootstrap::Bool=!isempty(bootstrap_list),
                       verbose::Bool = false)
    global use_ccache

    # Convert platform to a triplet, but strip out the ABI parts
    target = aatriplet(platform)
    host_target = aatriplet(host_platform)

    # Prefix, libdir, etc...
    prefix = "/workspace/destdir"
    host_prefix = "/workspace/$(triplet(host_platform))/destdir"
    if Sys.iswindows(platform)
        libdir = "$(prefix)/bin"
    else
        libdir = "$(prefix)/lib"
    end
    if Sys.iswindows(host_platform)
        host_libdir = "$(host_prefix)/bin"
    else
        host_libdir = "$(host_prefix)/lib"
    end

    if get(stdout, :color, false)
        PS1 = string(
            raw"\[",
            Base.text_colors[:light_blue],
            raw"\]",
            "sandbox",
            raw"\[",
            Base.text_colors[:normal],
            raw"\]",
            ":",
            raw"\[",
            Base.text_colors[:yellow],
            raw"\]",
            raw"${PWD//$WORKSPACE/$\{WORKSPACE\}}",
            raw"\[",
            Base.text_colors[:normal],
            raw"\]",
            raw" \$ ",
        )
    else
        PS1 = raw"sandbox:${PWD//$WORKSPACE/$\{WORKSPACE\}} $ "
    end

    # Base mappings
    mapping = Dict(
        # Platform information (we save a `bb_target` because sometimes `target` gets
        # overwritten in `./configure`, and we want tools like `uname` to still see it)
        "bb_target" => target,
        "target" => target,
        # Also give people access to the full `-cxxYY` and `-libgfortranX` triplet if they really want it
        "bb_full_target" => triplet(platform),
        "rust_target" => map_rust_target(platform),
        "rust_host" => map_rust_target(host_platform),
        "nproc" => "$(get(ENV, "BINARYBUILDER_NPROC", Sys.CPU_THREADS))",
        "nbits" => string(nbits(platform)),
        "proc_family" => string(proc_family(platform)),
        "dlext" => platform_dlext(platform),
        "exeext" => platform_exeext(platform),
        "PATH" => "/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin",
        "MACHTYPE" => "x86_64-linux-musl",

        # Set location parameters
        "WORKSPACE" => "/workspace",
        "prefix" => prefix,
        "bindir" => "$(prefix)/bin",
        "libdir" => libdir,
        "includedir" => "$(prefix)/include",

        # Set variables for the host prefix
        "host_prefix" => host_prefix,
        "host_bindir" => "$(host_prefix)/bin",
        "host_libdir" => host_libdir,
        "host_includedir" => "$(host_prefix)/include",

        # Fancyness!
        "USER" => get(ENV, "USER", "julia"),
        # Docker filters out `PS1` so we route around it
        "HIDDEN_PS1" => PS1,
        "VERBOSE" => "$(verbose)",
        "V" => "$(verbose)",
        "HISTFILE"=>"/meta/.bash_history",
        "TERM" => "screen",
        "SRC_NAME" => src_name,
        # The environment inherits the `SHELL` variable from the host, but some
        # tools refer to this variable, make it consistent with our environment
        "SHELL" => "/bin/bash",
    )

    # If we're bootstrapping, that's it, quit out.
    if bootstrap
        return mapping
    end

    # Helper for generating the library include path for a target.  MacOS, as usual,
    # puts things in slightly different place.
    function target_lib_dir(p::AbstractPlatform)
        t = aatriplet(p)
        if Sys.isapple(p)
            return "/opt/$(t)/$(t)/lib:/opt/$(t)/lib"
        else
            return "/opt/$(t)/$(t)/lib64:/opt/$(t)/$(t)/lib"
        end
    end

    function GOARM(p::AbstractPlatform)
        # See https://github.com/golang/go/wiki/GoArm#supported-architectures
        if arch(p) == "armv6l"
            return "6"
        elseif arch(p) == "armv7l"
            return "7"
        else
            return ""
        end
    end

    function csl_paths(p::AbstractPlatform)
        libcs = if Sys.islinux(p) && proc_family(p) == "intel" && libc(p) == "musl"
            # We need to push musl directories before glibc ones
            ("musl", "glibc")
        else
            ("glibc", "musl")
        end

        archs = if Sys.islinux(p) && proc_family(p) == "intel" && arch(p) == "i686"
            # We need to push i686 directories before x86_64 ones
            ("i686", "x86_64")
        else
            ("x86", "i686_64")
        end

        return join(["/usr/lib/csl-$(libc)-$(arch)" for libc in libcs, arch in archs], ":")
    end

    merge!(mapping, Dict(
        "PATH" => join((
            # First things first, our compiler wrappers trump all
            "/opt/bin/$(triplet(platform))",
            # Allow users to use things like x86_64-linux-gnu here
            "/opt/$(target)/bin",
            # Also wrappers for the host
            "/opt/bin/$(triplet(host_platform))",
            "/opt/$(host_target)/bin",
            # Default alpine PATH
            mapping["PATH"],
            # Host tools, installed as `HostBuildDependency`
            mapping["host_bindir"],
            # Finally, dependency tools
            mapping["bindir"],
        ), ":"),

        "LD_LIBRARY_PATH" => join((
           # Start with a default path
           "/usr/local/lib64:/usr/local/lib:/usr/lib64:/usr/lib",
            # Add our loader directories
            "/lib64:/lib",
            # Add our CSL libraries for all architectures that can natively run within this environment
            csl_paths(host_platform),
            # Libdir of the host platform, to run programs in `HostBuildDependency`
            "$(host_libdir)",
            # Add our target/host-specific library directories for compiler support libraries
            target_lib_dir(host_platform),
            target_lib_dir(platform),
            # Finally, dependencies
            "$(prefix)/lib64:$(prefix)/lib",
        ), ":"),

        # Default mappings for some tools
        "CC" => "cc",
        "CXX" => "c++",
        "FC" => "gfortran",
        "GO" => "go",
        "RUSTC" => "rustc",
        "CARGO" => "cargo",

        # Go stuff
        "GOCACHE" => "/workspace/.gocache",
        "GOPATH" => "/workspace/.gopath",
        "GOARM" => GOARM(platform),

        # Rust stuff
        "CARGO_BUILD_TARGET" => map_rust_target(platform),
        "CARGO_HOME" => "/opt/$(host_target)",
        "RUSTUP_HOME" => "/opt/$(host_target)",
        # TODO: we'll need a way to parameterize this toolchain number
        "RUSTUP_TOOLCHAIN" => "1.43.0-$(map_rust_target(host_platform))",

        # We conditionally add on some compiler flags; we'll cull empty ones at the end
        "USE_CCACHE" => "$(use_ccache)",
        "LLVM_TARGET" => target,
        "LLVM_HOST_TARGET" => host_target,

        # Let the user parameterize their scripts for toolchain locations
        "CMAKE_HOST_TOOLCHAIN" => "/opt/toolchains/$(triplet(host_platform))/host_$(host_target).cmake",
        "CMAKE_TARGET_TOOLCHAIN" => "/opt/toolchains/$(triplet(platform))/target_$(target).cmake",
        "MESON_HOST_TOOLCHAIN" => "/opt/toolchains/$(triplet(host_platform))/$(host_target).meson",
        "MESON_TARGET_TOOLCHAIN" => "/opt/toolchains/$(triplet(platform))/$(target).meson",

        # We should always be looking for packages already in the prefix
        "PKG_CONFIG_PATH" => "$(prefix)/lib/pkgconfig:$(prefix)/lib64/pkgconfig:$(prefix)/share/pkgconfig",
        "PKG_CONFIG_SYSROOT_DIR" => prefix,

        # ccache options
        "CCACHE_COMPILERCHECK" => "content",

        # Things to help us step closer to reproducible builds; eliminate timestamp
        # variability within our binaries.
        "SOURCE_DATE_EPOCH" => "0",
        "ZERO_AR_DATE" => "1",
    ))

    # If we're on macOS, we give a hint to things like `configure` that they should use this as the linker
    if Sys.isapple(platform)
        mapping["LD"] = "/opt/bin/$(triplet(platform))/ld"
        mapping["MACOSX_DEPLOYMENT_TARGET"] = "10.8"
    end

    # There is no broad agreement on what host compilers should be called,
    # so we set all the environment variables that we've seen them called
    # and hope for the best.
    for host_map in (tool -> "HOST$(tool)", tool -> "$(tool)_FOR_BUILD", tool -> "BUILD_$(tool)", tool -> "$(tool)_BUILD")
        # Use full path to avoid collisions when the target is similar to the
        # host (e.g., `x86_64-linux-musl-cxx03` and `x86_64-linux-musl-cxx11`)
        host_bin_dir = "/opt/bin/$(triplet(host_platform))"

        # First, do the simple tools where it's just X => $(host_target)-x:
        for tool in ("AR", "AS", "LD", "LIPO", "NM", "RANLIB", "READELF", "OBJCOPY", "OBJDUMP", "STRIP")
            mapping[host_map(tool)] = "$(host_bin_dir)/$(host_target)-$(lowercase(tool))"
        end

        # Next, the more custom tool mappings
        for (env_name, tool) in (
            "CC" => "$(host_bin_dir)/$(host_target)-gcc",
            "CXX" => "$(host_bin_dir)/$(host_target)-g++",
            "DSYMUTIL" => "dsymutil",
            "FC" => "$(host_bin_dir)/$(host_target)-gfortran"
           )
            mapping[host_map(env_name)] = tool
        end
    end

    # There is no easy way to automatically determine the version of glibc for
    # all platforms, but some build systems want to know it.  Let's emulate with
    # the `GNU_LIBC_VERSION` environment variable what `getconf
    # GNU_LIBC_VERSION` would return, if it worked.
    if libc(platform) === "glibc"
        # This should be kept in sync with the version of glibc used in
        # https://github.com/JuliaPackaging/Yggdrasil/blob/master/0_RootFS/gcc_common.jl
        if arch(platform) in ("x86_64", "i686")
            mapping["GNU_LIBC_VERSION"] = "glibc 2.12.2"
        elseif arch(platform) in ("armv7l", "aarch64")
            mapping["GNU_LIBC_VERSION"] = "glibc 2.19"
        elseif arch(platform) === "powerpc64le"
            mapping["GNU_LIBC_VERSION"] = "glibc 2.17"
        end
    end

    return mapping
end

runner_override = ""
function preferred_runner()
    global runner_override
    if runner_override != ""
        if runner_override in ["userns", "privileged"]
            return UserNSRunner
        elseif runner_override in ["docker"]
            return DockerRunner
        end
    end

    @static if Sys.islinux()
        return UserNSRunner
    else
        return DockerRunner
    end
end

"""
    runshell(platform::AbstractPlatform = HostPlatform())

Launch an interactive shell session within the user namespace, with environment
setup to target the given `platform`.
"""
function runshell(platform::AbstractPlatform = HostPlatform(); kwargs...)
    runshell(preferred_runner(), platform; kwargs...)
end

function runshell(r::Runner, args...; kwargs...)
    run_interactive(r, `/bin/bash -l`, args...; kwargs...)
end

function runshell(::Type{R}, platform::AbstractPlatform = HostPlatform(); verbose::Bool=false,kwargs...) where {R <: Runner}
    return runshell(R(pwd(); cwd="/workspace/", platform=platform, verbose=verbose, kwargs...); verbose=verbose)
end

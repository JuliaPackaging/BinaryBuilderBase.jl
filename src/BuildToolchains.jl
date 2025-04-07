abstract type AbstractBuildToolchain{C} end

struct CMake{C} <: AbstractBuildToolchain{C} end
struct Meson{C} <: AbstractBuildToolchain{C} end

c_compiler(::AbstractBuildToolchain{:clang}) = "clang"
cxx_compiler(::AbstractBuildToolchain{:clang}) = "clang++"
c_compiler(::AbstractBuildToolchain{:gcc}) = "gcc"
cxx_compiler(::AbstractBuildToolchain{:gcc}) = "g++"
fortran_compiler(::AbstractBuildToolchain) = "gfortran"

function cmake_arch(p::AbstractPlatform)
    if arch(p) == "powerpc64le"
        return "ppc64le"
    else
        return arch(p)
    end
end

function cmake_os(p::AbstractPlatform)
    if Sys.islinux(p)
        return "Linux"
    elseif Sys.isfreebsd(p)
        return "FreeBSD"
    elseif Sys.isapple(p)
        return "Darwin"
    elseif Sys.iswindows(p)
        return "Windows"
    else
        return "Unknown"
    end
end

lld_string(p::AbstractPlatform) = Sys.isapple(p) ? "ld64.lld" : "ld.lld"
function linker_string(bt::CMake{:gcc}, p::AbstractPlatform, clang_use_lld)
    target = triplet(p)
    aatarget = aatriplet(p)
    return "/opt/bin/$(target)/$(aatarget)-ld"
end

function linker_string(bt::CMake{:clang}, p::AbstractPlatform, clang_use_lld)
    target = triplet(p)
    aatarget = aatriplet(p)
    return clang_use_lld ? "/opt/bin/$(target)/$(lld_string(p))" : "/opt/bin/$(target)/$(aatarget)-ld"
end

function toolchain_file(bt::CMake, p::AbstractPlatform, host_platform::AbstractPlatform; is_host::Bool=false, clang_use_lld::Bool=false)
    target = triplet(p)
    aatarget = aatriplet(p)

    # In order to get the version of the host system we need to call `/bin/uname -r`.
    file = """
        # CMake toolchain file for $(c_compiler(bt)) running on $(target)
        set(CMAKE_HOST_SYSTEM_NAME $(cmake_os(host_platform)))
        set(CMAKE_HOST_SYSTEM_PROCESSOR $(cmake_arch(host_platform)))
        execute_process(COMMAND /bin/uname -r OUTPUT_VARIABLE CMAKE_HOST_SYSTEM_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE)
        """

    if !is_host
        # CMake checks whether `SYSTEM_NAME` is set manually to decide whether the current
        # build is a cross-compilation or not:
        # <https://cmake.org/cmake/help/latest/variable/CMAKE_CROSSCOMPILING.html>.  We
        # always set `HOST_SYSTEM_NAME`, but set `SYSTEM_NAME` only for the target
        # toolchain.
        file *= """
        set(CMAKE_SYSTEM_NAME $(cmake_os(p)))
        set(CMAKE_SYSTEM_PROCESSOR $(cmake_arch(p)))
        """
    end

    if Sys.isapple(p)
        darwin_ver = something(os_version(p), v"14.5.0")
        maj_ver = darwin_ver.major
        min_ver = darwin_ver.minor
        file *= """
        set(CMAKE_SYSTEM_VERSION $(maj_ver).$(min_ver))
        set(DARWIN_MAJOR_VERSION $(maj_ver))
        set(DARWIN_MINOR_VERSION $(min_ver))

        set(CMAKE_SYSROOT /opt/$(aatarget)/$(aatarget)/sys-root)
        set(CMAKE_SYSTEM_FRAMEWORK_PATH
            \${CMAKE_SYSROOT}/System/Library/Frameworks
            \${CMAKE_SYSROOT}/System/Library/PrivateFrameworks
        )
        """
    else
        if !is_host
            file *= """
        execute_process(COMMAND /usr/bin/uname -r OUTPUT_VARIABLE CMAKE_SYSTEM_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE)

        """
        end
        file *= """
        set(CMAKE_SYSROOT /opt/$(aatarget)/$(aatarget)/sys-root/)
        """
    end

    if arch(p) == "riscv64"
        # RISCV libraries are in a subdirectory corresponding to the ABI of the processor
        file *= """
        set(CMAKE_SYSTEM_LIBRARY_PATH \${CMAKE_SYSROOT}/usr/lib64/lp64d)
        """
    end

    file *= """
        set(CMAKE_INSTALL_PREFIX \$ENV{prefix})

        set(CMAKE_C_COMPILER   /opt/bin/$(target)/$(aatarget)-$(c_compiler(bt)))
        set(CMAKE_CXX_COMPILER /opt/bin/$(target)/$(aatarget)-$(cxx_compiler(bt)))
        set(CMAKE_Fortran_COMPILER /opt/bin/$(target)/$(aatarget)-$(fortran_compiler(bt)))

        set(CMAKE_LINKER  $(linker_string(bt, p, clang_use_lld)))
        set(CMAKE_OBJCOPY /opt/bin/$(target)/$(aatarget)-objcopy)

        set(CMAKE_AR     /opt/bin/$(target)/$(aatarget)-ar)
        set(CMAKE_NM     /opt/bin/$(target)/$(aatarget)-nm)
        set(CMAKE_RANLIB /opt/bin/$(target)/$(aatarget)-ranlib)

        if( \$ENV{CC} MATCHES ccache )
            set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE ccache)
        endif()
        """
end

meson_c_args(p::AbstractPlatform, envs::Dict{String,String}; is_host::Bool=false) =
    ["'-I$(envs[is_host ? "host_includedir" : "includedir"])'"]
meson_cxx_args(p::AbstractPlatform, envs::Dict{String,String}; is_host::Bool=false) = meson_c_args(p, envs; is_host)
meson_objc_args(p::AbstractPlatform, envs::Dict{String,String}; is_host::Bool=false) = push!(meson_c_args(p, envs; is_host), "'-x'", "'objective-c'")
meson_fortran_args(p::AbstractPlatform, envs::Dict{String,String}; is_host::Bool=false) = meson_c_args(p, envs; is_host)

function meson_c_link_args(p::AbstractPlatform, envs::Dict{String,String}; is_host::Bool=false)
    prefix, libdir = envs[is_host ? "host_prefix" : "prefix"], envs[is_host ? "host_libdir" : "libdir"]
    if arch(p) == "powerpc64le" && Sys.islinux(p)
        return ["'-L$(libdir)'", "'-Wl,-rpath-link,$(prefix)/lib64'"]
    else
        return ["'-L$(libdir)'"]
    end
end
meson_cxx_link_args(p::AbstractPlatform, envs::Dict{String,String}; is_host::Bool=false) = meson_c_link_args(p, envs; is_host)
meson_objc_link_args(p::AbstractPlatform, envs::Dict{String,String}; is_host::Bool=false) = meson_c_link_args(p, envs; is_host)
meson_fortran_link_args(p::AbstractPlatform, envs::Dict{String,String}; is_host::Bool=false) = meson_c_link_args(p, envs; is_host)

# We can run native programs only if the platform matches the default host
# platform, but when this is `x86_64-linux-musl` we can run executables for
# * i686-linux-gnu
# * x86_64-linux-gnu
# * x86_64-linux-musl
function meson_is_foreign(p::AbstractPlatform; is_host::Bool=false)
    is_host && return "false"
    if platforms_match(p, default_host_platform) ||
        (platforms_match(default_host_platform, Platform("x86_64", "linux"; libc="musl"))
         && Sys.islinux(p) && proc_family(p) == "intel" &&
             (libc(p) == "glibc" || (libc(p) == "musl" && arch(p) == "x86_64")))
        # Better to explicitly return the string we expect rather than
        # relying on the representation of the boolean values (even though
        # the result is the same)
        return "false"
    else
        return "true"
    end
end

# https://mesonbuild.com/Reference-tables.html#operating-system-names
meson_system(p::AbstractPlatform) = lowercase(cmake_os(p))

# https://github.com/mesonbuild/meson/blob/6e39dcad2fbd8d1c739e262b0e7b7d901cf1ce08/mesonbuild/environment.py#L412-L440
meson_cpu(p::AbstractPlatform) = cmake_arch(p)

# https://mesonbuild.com/Reference-tables.html#cpu-families
function meson_cpu_family(p::AbstractPlatform)
    if arch(p) == "powerpc64le"
        return "ppc64"
    elseif arch(p) == "i686"
        return "x86"
    elseif arch(p) == "x86_64"
        return "x86_64"
    elseif arch(p) == "aarch64"
        return "aarch64"
    elseif startswith(arch(p)::String, "arm")
        return "arm"
    elseif arch(p) == "riscv64"
        return "riscv64"
    end
end

function linker_string(bt::Meson{:gcc}, p::AbstractPlatform, clang_use_lld)
    target = triplet(p)
    aatarget = aatriplet(p)
    return "bfd"
end

function linker_string(bt::Meson{:clang}, p::AbstractPlatform, clang_use_lld)
    target = triplet(p)
    aatarget = aatriplet(p)
    return clang_use_lld ? "/opt/bin/$(target)/$(lld_string(p))" : "/opt/bin/$(target)/$(aatarget)-ld"
end

function toolchain_file(bt::Meson, p::AbstractPlatform, envs::Dict{String,String};
                        is_host::Bool=false, clang_use_lld::Bool=false)
    target = triplet(p)
    aatarget = aatriplet(p)
    clang_use_lld=false #Meson tries is best to misuse lld so don't use it for now
    return """
    [binaries]
    c = '/opt/bin/$(target)/$(aatarget)-$(c_compiler(bt))'
    cpp = '/opt/bin/$(target)/$(aatarget)-$(cxx_compiler(bt))'
    fortran = '/opt/bin/$(target)/$(aatarget)-$(fortran_compiler(bt))'
    objc = '/opt/bin/$(target)/$(aatarget)-cc'
    ar = '/opt/bin/$(target)/$(aatarget)-ar'
    ld = '$(linker_string(bt, p, clang_use_lld))'
    cpp_ld = '$(linker_string(bt, p, clang_use_lld))'
    c_ld = '$(linker_string(bt, p, clang_use_lld))'
    nm = '/opt/bin/$(target)/$(aatarget)-nm'
    strip = '/opt/bin/$(target)/$(aatarget)-strip'
    pkgconfig = '/usr/bin/pkg-config'

    [built-in options]
    c_args = [$(join(meson_c_args(p, envs; is_host), ", "))]
    cpp_args = [$(join(meson_cxx_args(p, envs; is_host), ", "))]
    fortran_args = [$(join(meson_fortran_args(p, envs; is_host), ", "))]
    objc_args = [$(join(meson_objc_args(p, envs; is_host), ", "))]
    c_link_args = [$(join(meson_c_link_args(p, envs; is_host), ", "))]
    cpp_link_args = [$(join(meson_cxx_link_args(p, envs; is_host), ", "))]
    fortran_link_args = [$(join(meson_fortran_link_args(p, envs; is_host), ", "))]
    objc_link_args = [$(join(meson_objc_link_args(p, envs; is_host), ", "))]
    prefix = '$(envs[is_host ? "host_prefix" : "prefix"])'

    [properties]
    needs_exe_wrapper = $(meson_is_foreign(p; is_host))
    cmake_toolchain_file = '$(envs[is_host ? "CMAKE_HOST_TOOLCHAIN" : "CMAKE_TARGET_TOOLCHAIN"])'
    cmake_defaults = false

    [build_machine]
    system = 'linux'
    cpu_family = 'x86_64'
    cpu = 'x86_64'
    endian = 'little'

    [host_machine]
    system = '$(meson_system(p))'
    cpu_family = '$(meson_cpu_family(p))'
    cpu = '$(meson_cpu(p))'
    endian = 'little'
    """
end

function generate_toolchain_files!(platform::AbstractPlatform, envs::Dict{String,String},
                                   toolchains_path::AbstractString;
                                   host_platform::AbstractPlatform = default_host_platform,
                                   clang_use_lld::Bool = false,
                                   )

    # Generate the files fot bot the host and the target platforms
    for p in unique((platform, host_platform))
        dir = joinpath(toolchains_path, triplet(p))
        mkpath(dir)

        for compiler in (:clang, :gcc)
            # Target toolchains
            if platforms_match(p, platform)
                write(joinpath(dir, "target_$(aatriplet(p))_$(compiler).cmake"), toolchain_file(CMake{compiler}(), p, host_platform; is_host=false, clang_use_lld=clang_use_lld))
                write(joinpath(dir, "target_$(aatriplet(p))_$(compiler).meson"), toolchain_file(Meson{compiler}(), p, envs; is_host=false, clang_use_lld=clang_use_lld))
            end
            # Host toolchains
            if platforms_match(p, host_platform)
                write(joinpath(dir, "host_$(aatriplet(p))_$(compiler).cmake"), toolchain_file(CMake{compiler}(), p, host_platform; is_host=true, clang_use_lld=clang_use_lld))
                write(joinpath(dir, "host_$(aatriplet(p))_$(compiler).meson"), toolchain_file(Meson{compiler}(), p, envs; is_host=true, clang_use_lld=clang_use_lld))
            end
        end

        symlink_if_exists(target, link) = ispath(joinpath(dir, target)) && symlink(target, link)

        # On FreeBSD and MacOS we actually want to default to clang, otherwise gcc
        if prefer_clang(p)
            symlink_if_exists("host_$(aatriplet(p))_clang.cmake", joinpath(dir, "host_$(aatriplet(p)).cmake"))
            symlink_if_exists("host_$(aatriplet(p))_clang.meson", joinpath(dir, "host_$(aatriplet(p)).meson"))
            symlink_if_exists("target_$(aatriplet(p))_clang.cmake", joinpath(dir, "target_$(aatriplet(p)).cmake"))
            symlink_if_exists("target_$(aatriplet(p))_clang.meson", joinpath(dir, "target_$(aatriplet(p)).meson"))
        else
            symlink_if_exists("host_$(aatriplet(p))_gcc.cmake", joinpath(dir, "host_$(aatriplet(p)).cmake"))
            symlink_if_exists("host_$(aatriplet(p))_gcc.meson", joinpath(dir, "host_$(aatriplet(p)).meson"))
            symlink_if_exists("target_$(aatriplet(p))_gcc.cmake", joinpath(dir, "target_$(aatriplet(p)).cmake"))
            symlink_if_exists("target_$(aatriplet(p))_gcc.meson", joinpath(dir, "target_$(aatriplet(p)).meson"))
        end
    end
end

function cargo_config_file!(dir::AbstractString, platform::AbstractPlatform;
                            host_platform::AbstractPlatform=default_host_platform,
                            )
    # Generate "${CARGO_HOME}/config.toml" file for Cargo where we give it the linkers for
    # the host and target platforms.
    open(joinpath(dir, "config.toml"), "w") do io
        print(io, """
        # Configuration file for `cargo`
        """)
        for p in unique(abi_agnostic.((platform, host_platform)))
            # Use `aatriplet` for the linker to match how the wrappers are written in
            # https://github.com/JuliaPackaging/BinaryBuilderBase.jl/blob/30d056ef68f81dca9cb91ededcce6b68c6466b37/src/Runner.jl#L599.
            print(io, """
            [target.$(map_rust_target(p))]
            linker = "$(aatriplet(p))-cc"
            """)
        end
        print(io, """
                  # Use sparse registry for quick updates
                  [registries.crates-io]
                  protocol = 'sparse'
                  """)
    end
end

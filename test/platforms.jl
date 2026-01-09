using Test
using Base.BinaryPlatforms
using BinaryBuilderBase
using BinaryBuilderBase: abi_agnostic, get_concrete_platform, march, platform_dlext, platform_exeext,
                         nbits, proc_family, default_host_platform, parse_platform

@testset "Supported Platforms" begin
    all = supported_platforms()
    opt_out_specific = supported_platforms(exclude=[Platform("x86_64", "linux"; libc="glibc")])
    opt_out_fx = supported_platforms(exclude=Sys.islinux)

    @test length(all) == length(opt_out_specific)+1
    @test any(opt_out_specific .== [Platform("i686", "linux", libc="glibc")])
    @test !any(opt_out_fx .== [Platform("i686", "linux", libc="glibc")])

    @test sort(
        [
            Platform("x86_64", "windows"),
            Platform("i686", "linux"; libc="musl"),
            Platform("i686", "linux"; libc="glibc"),
            Platform("x86_64", "macos")
        ], by = triplet) == [
            Platform("i686", "linux"; libc="glibc"),
            Platform("i686", "linux"; libc="musl"),
            Platform("x86_64", "macos"),
            Platform("x86_64", "windows"),
        ]
end

@testset "abi_agnostic" begin
    p = Platform("x86_64", "linux"; libc="musl", libgfortran_version=v"3", cxxstring_abi="cxx03", libstdcxx_version=v"3.4.26")
    @test abi_agnostic(p) == Platform("x86_64", "linux"; libc="musl")
end

@testset "AnyPlatform" begin
    # Test some AnyPlatform properties
    @test triplet(AnyPlatform()) == "any"
    @test abi_agnostic(AnyPlatform()) === AnyPlatform()
    @test arch(AnyPlatform()) == "any"
    @test repr(AnyPlatform()) == "AnyPlatform"

    # In the build environment we want AnyPlatform to look like `default_host_platform`
    @test get_concrete_platform(
            AnyPlatform();
            compilers = [:c],
            preferred_gcc_version = v"7",
            preferred_llvm_version = v"9",
        ) == get_concrete_platform(
            default_host_platform;
            compilers = [:c],
            preferred_gcc_version = v"7",
            preferred_llvm_version = v"9",
        )
    @test BinaryBuilderBase.choose_shards(AnyPlatform()) == BinaryBuilderBase.choose_shards(default_host_platform)
    @test BinaryBuilderBase.aatriplet(AnyPlatform()) == BinaryBuilderBase.aatriplet(default_host_platform)

    # Make sure `AnyPlatform` matches all platforms we can possibly support.
    @test all(p -> platforms_match(AnyPlatform(), p),
              expand_microarchitectures(expand_gfortran_versions(expand_cxxstring_abis(supported_platforms(; experimental=true)))))

    # Make sure `AnyPlatform` matches all platforms we can possibly support.
    @test all(p -> BinaryBuilderBase.platforms_match_with_sanitize(AnyPlatform(), p),
              expand_microarchitectures(expand_gfortran_versions(expand_cxxstring_abis(supported_platforms(; experimental=true)))))
end

@testset "Target properties" begin
    for p in [Platform("i686", "linux"), Platform("i686", "windows"), Platform("armv7l", "linux")]
        @test nbits(p) == 32
    end

    for p in [Platform("x86_64", "linux"), Platform("x86_64", "windows"), Platform("aarch64", "linux"),
              Platform("powerpc64le", "linux"), Platform("riscv64", "linux"), Platform("x86_64", "macos")]
        @test nbits(p) == 64
    end

    for p in [Platform("x86_64", "linux"), Platform("x86_64", "macos"), Platform("i686", "windows")]
        @test proc_family(p) == "intel"
    end
    for p in [Platform("aarch64", "linux"; libc="musl"), Platform("armv7l", "linux")]
        @test proc_family(p) == "arm"
    end
    @test proc_family(Platform("powerpc64le", "linux")) == "power"
    @test proc_family(Platform("riscv64", "linux")) == "riscv"

    for p in [Platform("x86_64", "linux"), Platform("x86_64", "freebsd"), Platform("powerpc64le", "linux"),
              Platform("riscv64", "linux"), Platform("x86_64", "macos")]
        @test platform_exeext(p) == ""
    end
    @test platform_exeext(Platform("x86_64", "windows")) == ".exe"
    @test platform_exeext(Platform("i686", "windows")) == ".exe"

    @test platform_dlext(Platform("aarch64", "linux"; march="thunderx2")) == "so"
    @test platform_dlext(Platform("x86_64", "freebsd"; march="x86_64")) == "so"
    @test platform_dlext(Platform("x86_64", "macos"; march="avx512")) == "dylib"
    @test platform_dlext(Platform("i686", "windows"; cuda="10.1")) == "dll"
end

using BinaryBuilderBase: get_march_flags, get_all_arch_names, get_all_march_names
@testset "march flags" begin
    # test one that is common between gcc and clang
    @test get_march_flags("x86_64", "avx", "gcc") == ["-march=sandybridge", "-mtune=sandybridge"]

    # Test one that is different between gcc and clang
    @test get_march_flags("aarch64", "apple_m1", "gcc") == ["-march=armv8.5-a+aes+sha2+sha3+fp16fml+fp16+rcpc+dotprod", "-mcpu=cortex-a76"]
    @test get_march_flags("aarch64", "apple_m1", "clang") == ["-mcpu=apple-m1"]

    for compiler in ("gcc", "clang")
        # Make sure we get the right base microarchitecture for all compilers
        @test get_march_flags("aarch64", nothing, compiler) == get_march_flags("aarch64", "armv8_0",  compiler)
        @test get_march_flags("armv7l",  nothing, compiler) == get_march_flags("armv7l",  "armv7l",   compiler)
        @test get_march_flags("i686",    nothing, compiler) == get_march_flags("i686",    "pentium4", compiler)
        @test get_march_flags("x86_64",  nothing, compiler) == get_march_flags("x86_64",  "x86_64",   compiler)
    end

    # Get all architectures and all microarchitectures for the different architectures
    @test sort(get_all_arch_names()) == ["aarch64", "armv6l", "armv7l", "i686", "powerpc64le", "riscv64", "x86_64"]
    @test sort(get_all_march_names("x86_64")) == ["avx", "avx2", "avx512", "x86_64"]
    @test sort(get_all_march_names("armv7l")) == ["armv7l", "neonvfpv4"]
end

@testset "parse" begin
    @test parse_platform("host") == HostPlatform()
    @test parse_platform("any") == AnyPlatform()
    @test parse_platform("x86_64-linux") == Platform("x86_64", "linux")
    @test parse_platform("i686-w64-mingw32-cxx03") == Platform("i686", "windows"; cxxstring_abi="cxx03")
    @test parse_platform("aarch64-apple-darwin21-libgfortran4-cxx11") == Platform("aarch64", "macos"; os_version=v"21", cxxstring_abi="cxx11", libgfortran_version=v"4")
end

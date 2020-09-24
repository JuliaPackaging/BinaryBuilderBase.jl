using Test
using Base.BinaryPlatforms
using BinaryBuilderBase
using BinaryBuilderBase: abi_agnostic, get_concrete_platform, march, platform_dlext, platform_exeext,
                         nbits, proc_family

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

    # In the build environment we want AnyPlatform to look like x86_64-linux-musl
    @test get_concrete_platform(
            AnyPlatform();
            compilers = [:c],
            preferred_gcc_version = v"7",
            preferred_llvm_version = v"9",
        ) == get_concrete_platform(
            Platform("x86_64", "linux"; libc="musl");
            compilers = [:c],
            preferred_gcc_version = v"7",
            preferred_llvm_version = v"9",
        )
    @test BinaryBuilderBase.choose_shards(AnyPlatform()) == BinaryBuilderBase.choose_shards(Platform("x86_64", "linux"; libc="musl"))
    @test BinaryBuilderBase.aatriplet(AnyPlatform()) == BinaryBuilderBase.aatriplet(Platform("x86_64", "linux"; libc="musl"))
end

@testset "Target properties" begin
    for p in [Platform("i686", "linux"), Platform("i686", "windows"), Platform("armv7l", "linux")]
        @test nbits(p) == 32
    end

    for p in [Platform("x86_64", "linux"), Platform("x86_64", "windows"), Platform("aarch64", "linux"),
              Platform("powerpc64le", "linux"), Platform("x86_64", "macos")]
        @test nbits(p) == 64
    end

    for p in [Platform("x86_64", "linux"), Platform("x86_64", "macos"), Platform("i686", "windows")]
        @test proc_family(p) == "intel"
    end
    for p in [Platform("aarch64", "linux"; libc="musl"), Platform("armv7l", "linux")]
        @test proc_family(p) == "arm"
    end
    @test proc_family(Platform("powerpc64le", "linux")) == "power"

    for p in [Platform("x86_64", "linux"), Platform("x86_64", "freebsd"), Platform("powerpc64le", "linux"), Platform("x86_64", "macos")]
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
    @test get_march_flags("aarch64", "armv8_2_crypto", "gcc") == ["-march=armv8-a+lse+crc+rdma+aes+sha2", "-mtune=cortex-a76"]
    @test get_march_flags("aarch64", "armv8_2_crypto", "clang") == ["-march=armv8-a+lse+crc+rdm+aes+sha2", "-mtune=cortex-a76"]

    @test get_march_flags("aarch64", nothing, "gcc") == get_march_flags("aarch64", "armv8_0", "gcc")
    @test get_march_flags("armv7l", nothing, "clang") == get_march_flags("armv7l", "armv7l", "clang")
    @test get_march_flags("x86_64", nothing, "clang") == get_march_flags("x86_64", "x86_64", "clang")

    # Get all architectures and all microarchitectures for the different architectures
    @test sort(get_all_arch_names()) == ["aarch64", "armv6l", "armv7l", "i686", "powerpc64le", "x86_64"]
    @test sort(get_all_march_names("x86_64")) == ["avx", "avx2", "avx512", "x86_64"]
    @test sort(get_all_march_names("armv7l")) == ["armv7l", "neonvfpv4"]
end
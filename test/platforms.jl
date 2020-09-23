using Test
using BinaryPlatforms
using BinaryBuilderBase
using BinaryBuilderBase: abi_agnostic, get_concrete_platform, march

@testset "Supported Platforms" begin
    all = supported_platforms()
    opt_out_specific = supported_platforms(exclude=[Platform("x86_64", "linux"; libc="glibc)]")
    islin(x) = typeof(x) == Linux
    opt_out_fx = supported_platforms(exclude=islin)

    @test length(all) == length(opt_out_specific)+1
    @test any(opt_out_specific .== [Linux(:i686 , libc=:glibc)])
    @test !any(opt_out_fx .== [Linux(:i686 , libc=:glibc)])

    @test sort([Platform("x86_64", "windows"), Platform("i686", "linux"; libc="musl"), Platform("i686", "linux"; libc="glibc"), Platform("x86_64", "macos")],
               by = triplet) ==
                   [Platform("i686", "linux"; libc="glibc"), Platform("i686", "linux"; libc="musl"), Platform("x86_64", "macos"), Platform("x86_64", "windows")]
end

@testset "abi_agnostic" begin
    p = Platform("x86_64", "linux"; libc="musl", libgfortran_version=v"3", cxxstring_abi="cxx03", libstdcxx_version=v"3.4.26")
    @test abi_agnostic(p) == Platform("x86_64", "linux"; libc="musl")
end

@testset "AnyPlatform" begin
    # Test some AnyPlatform properties
    @test triplet(AnyPlatform()) == "any"
    @test abi_agnostic(AnyPlatform()) === AnyPlatform()
    @test arch(AnyPlatform()) == :x86_64
    @test repr(AnyPlatform()) == "AnyPlatform()"

    # In the build environment we want AnyPlatform to look like x86_64-linux-musl
    @test get_concrete_platform(AnyPlatform(); compilers = [:c], preferred_gcc_version = v"7", preferred_llvm_version = v"9") ==
        get_concrete_platform(Platform("x86_64", "linux"; libc="musl"); compilers = [:c], preferred_gcc_version = v"7", preferred_llvm_version = v"9")
    @test BinaryBuilderBase.choose_shards(AnyPlatform()) == BinaryBuilderBase.choose_shards(Platform("x86_64", "linux"; libc="musl"))
    @test BinaryBuilderBase.aatriplet(AnyPlatform()) == BinaryBuilderBase.aatriplet(Platform("x86_64", "linux"; libc="musl"))
end

@testset "Target properties" begin
    for p in [Platform("i686", "linux"), Platform("i686", "windows"), Platform("armv7l", "linux")]
        @test BinaryBuilderBase.nbits(p) == 32
    end

    for p in [Platform("x86_64", "linux"), Platform("x86_64", "windows"), Platform("aarch64", "linux"),
              Platform("powerpc64le", "linux"), MacOS()]
        @test BinaryBuilderBase.nbits(p) == 64
    end

    for p in [Platform("x86_64", "linux"), MacOS(), Platform("i686", "windows")]
        @test BinaryBuilderBase.proc_family(p) == :intel
    end
    for p in [Linux(:aarch64; libc=:musl), Platform("armv7l", "linux")]
        @test BinaryBuilderBase.proc_family(p) == :arm
    end
    @test BinaryBuilderBase.proc_family(Platform("powerpc64le)", "linux") == :power

    for p in [Platform("x86_64", "linux"), Platform("x86_64", "freebsd"), Platform("powerpc64le", "linux"), MacOS()]
        @test BinaryBuilderBase.exeext(p) == ""
    end
    @test BinaryBuilderBase.exeext(Platform("x86_64", "windows") == ".exe"
    @test BinaryBuilderBase.exeext(Platform("i686", "windows") == ".exe"

    @test BinaryPlatforms.platform_dlext(Platform("aarch64", "linux"; march="thunderx2")) == "so"
    @test BinaryPlatforms.platform_dlext(Platform("x86_64", "freebsd"; march="x86_64")) == "so"
    @test BinaryPlatforms.platform_dlext(Platform("x86_64", "macos"; march="avx512")) == "dylib"
    @test BinaryPlatforms.platform_dlext(Platform("i686", "windows"; cuda="10.1")) == "dll"
end

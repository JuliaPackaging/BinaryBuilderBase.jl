using Test
using Pkg, Pkg.PlatformEngines, Pkg.BinaryPlatforms
using BinaryBuilderBase
using BinaryBuilderBase: abi_agnostic

@testset "Supported Platforms" begin
    all = supported_platforms()
    opt_out_specific = supported_platforms(exclude=[Linux(:x86_64, libc=:glibc)])
    islin(x) = typeof(x) == Linux
    opt_out_fx = supported_platforms(exclude=islin)

    @test length(all) == length(opt_out_specific)+1
    @test any(opt_out_specific .== [Linux(:i686 , libc=:glibc)])
    @test !any(opt_out_fx .== [Linux(:i686 , libc=:glibc)])

    @test sort([Windows(:x86_64), Linux(:i686, libc=:musl), Linux(:i686, libc=:glibc), MacOS(:x86_64)],
               by = triplet) ==
                   [Linux(:i686, libc=:glibc), Linux(:i686, libc=:musl), MacOS(:x86_64), Windows(:x86_64)]
end

@testset "AnyPlatform" begin
    # Test some AnyPlatform properties
    @test triplet(AnyPlatform()) == "any"
    @test Pkg.BinaryPlatforms.platform_name(AnyPlatform()) == "AnyPlatform"
    @test abi_agnostic(AnyPlatform()) === AnyPlatform()
    @test arch(AnyPlatform()) == :x86_64
    @test repr(AnyPlatform()) == "AnyPlatform()"

    # In the build environment we want AnyPlatform to look like x86_64-linux-musl
    @test BinaryBuilderBase.get_concrete_platform(AnyPlatform(); compilers = [:c], preferred_gcc_version = v"7", preferred_llvm_version = v"9") ==
        BinaryBuilderBase.get_concrete_platform(Linux(:x86_64, libc=:musl); compilers = [:c], preferred_gcc_version = v"7", preferred_llvm_version = v"9")
    @test BinaryBuilderBase.choose_shards(AnyPlatform()) == BinaryBuilderBase.choose_shards(Linux(:x86_64, libc=:musl))
    @test BinaryBuilderBase.aatriplet(AnyPlatform()) == BinaryBuilderBase.aatriplet(Linux(:x86_64, libc=:musl))
end

@testset "Target properties" begin
    for p in [Linux(:i686), Windows(:i686), Linux(:armv7l)]
        @test BinaryBuilderBase.nbits(p) == 32
    end

    for p in [Linux(:x86_64), Windows(:x86_64), Linux(:aarch64),
              Linux(:powerpc64le), MacOS()]
        @test BinaryBuilderBase.nbits(p) == 64
    end

    for p in [Linux(:x86_64), MacOS(), Windows(:i686)]
        @test BinaryBuilderBase.proc_family(p) == :intel
    end
    for p in [Linux(:aarch64; libc=:musl), Linux(:armv7l)]
        @test BinaryBuilderBase.proc_family(p) == :arm
    end
    @test BinaryBuilderBase.proc_family(Linux(:powerpc64le)) == :power

    for p in [Linux(:aarch64), FreeBSD(:x86_64)]
        @test BinaryBuilderBase.dlext(p) == "so"
    end
    @test BinaryBuilderBase.dlext(MacOS()) == "dylib"
    @test BinaryBuilderBase.dlext(Windows(:i686)) == "dll"

    for p in [Linux(:x86_64), FreeBSD(:x86_64), Linux(:powerpc64le), MacOS()]
        @test BinaryBuilderBase.exeext(p) == ""
    end
    @test BinaryBuilderBase.exeext(Windows(:x86_64)) == ".exe"
    @test BinaryBuilderBase.exeext(Windows(:i686)) == ".exe"
end

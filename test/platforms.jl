using Test
using Pkg, Pkg.PlatformEngines, Pkg.BinaryPlatforms, Pkg.Artifacts
using BinaryBuilderBase
using BinaryBuilderBase: abi_agnostic, get_concrete_platform, march

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

@testset "ExtendedPlatform" begin
    p = ExtendedPlatform(Linux(:x86_64; libc=:musl); march = "avx", cuda = "9.2")
    @test p.p == Linux(:x86_64, libc=:musl)
    @test p.ext == Dict("march" => "avx", "cuda" => "9.2")
    @test BinaryPlatforms.platform_name(p) == "ExtendedPlatform"
    @test BinaryPlatforms.arch(p) == :x86_64
    @test BinaryPlatforms.libc(p) == :musl
    @test BinaryPlatforms.call_abi(p) == nothing
    @test BinaryPlatforms.compiler_abi(p) == CompilerABI()
    @test BinaryPlatforms.triplet(p) == "x86_64-linux-musl-cuda+9.2-march+avx"
    @test abi_agnostic(p) == Linux(:x86_64, libc=:musl)
    @test aatriplet(p) == "x86_64-linux-musl"
    @test replace_cxxstring_abi(p, :cxx03) == ExtendedPlatform(Linux(:x86_64; libc=:musl, compiler_abi=CompilerABI(; cxxstring_abi=:cxx03)); march = "avx", cuda = "9.2")
    @test replace_libgfortran_version(p, v"4") == ExtendedPlatform(Linux(:x86_64; libc=:musl, compiler_abi=CompilerABI(; libgfortran_version=v"4")); march = "avx", cuda = "9.2")
    # The concrete platform has C++11 strinb ABI because march=avx requires GCC v5
    @test get_concrete_platform(p; compilers = [:c], preferred_gcc_version = v"4.8", preferred_llvm_version = v"9") == ExtendedPlatform(Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(libgfortran_version=v"3", cxxstring_abi=:cxx11)); march="avx", cuda="9.2")
    @test ExtendedPlatform(p; cuda="9.2", foo="bar") == ExtendedPlatform(Linux(:x86_64, libc=:musl); march="avx", cuda="9.2", foo="bar")
    @test ExtendedPlatform(p; foo="bar") == ExtendedPlatform(Linux(:x86_64, libc=:musl); march="avx", cuda="9.2", foo="bar")
    @test_throws ErrorException ExtendedPlatform(p; cuda="10.1")
    # We have to split in this way the test on the representation of the type
    # because it may depend on the order with which the keys are extracted from
    # the dictionary
    @test startswith(repr(p), "ExtendedPlatform(Linux(:x86_64, libc=:musl);")
    @test occursin("march=\"avx\"", repr(p))
    @test occursin("cuda=\"9.2\"", repr(p))
    @test endswith(repr(p), ")")
    # Make sure the round trip works
    @test parse(ExtendedPlatform, triplet(p)) == p
    meta = Dict{String,String}()
    Artifacts.pack_platform!(meta, p)
    @test meta == Dict("arch" => "x86_64","libc" => "musl","march" => "avx","os" => "linux")

    p = ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5", cxxstring_abi=:cxx03)); microarchitecture="skylake_avx512", cuda="10.1", cuda_capability="52")
    @test p.p == Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5", cxxstring_abi=:cxx03))
    @test p.ext == Dict("microarchitecture" => "skylake_avx512","cuda_capability" => "52","cuda" => "10.1")
    @test BinaryPlatforms.platform_name(p) == "ExtendedPlatform"
    @test BinaryPlatforms.arch(p) == :powerpc64le
    @test BinaryPlatforms.libc(p) == :glibc
    @test BinaryPlatforms.call_abi(p) == nothing
    @test BinaryPlatforms.compiler_abi(p) == CompilerABI(libgfortran_version=v"5", cxxstring_abi=:cxx03)
    @test BinaryPlatforms.triplet(p) == "powerpc64le-linux-gnu-libgfortran5-cxx03-cuda+10.1-cuda_capability+52-microarchitecture+skylake_avx512"
    @test replace_cxxstring_abi(p, :cxx11) == ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5", cxxstring_abi=:cxx11)); microarchitecture="skylake_avx512", cuda="10.1", cuda_capability="52")
    @test replace_libgfortran_version(p, v"3") == ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"3", cxxstring_abi=:cxx03)); microarchitecture="skylake_avx512", cuda="10.1", cuda_capability="52")
    @test abi_agnostic(p) == Linux(:powerpc64le, libc=:glibc)
    @test aatriplet(p) == "powerpc64le-linux-gnu"
    @test get_concrete_platform(p; compilers = [:c, :go], preferred_gcc_version = v"8", preferred_llvm_version = v"6") == ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5", cxxstring_abi=:cxx03)); microarchitecture="skylake_avx512", cuda_capability="52", cuda="10.1")
    @test ExtendedPlatform(p; cuda="10.1", foo="bar") == ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5.0.0", cxxstring_abi=:cxx03)); microarchitecture="skylake_avx512", cuda_capability="52", cuda="10.1", foo="bar")
    @test ExtendedPlatform(p; foo="bar") == ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5.0.0", cxxstring_abi=:cxx03)); microarchitecture="skylake_avx512", cuda_capability="52", cuda="10.1", foo="bar")
    @test_throws ErrorException ExtendedPlatform(p; cuda="10.1", cuda_capability="80")
    @test startswith(repr(p), "ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v\"5.0.0\", cxxstring_abi=:cxx03)); ")
    @test occursin("microarchitecture=\"skylake_avx512\"", repr(p))
    @test occursin("cuda=\"10.1\"", repr(p))
    @test occursin("cuda_capability=\"52\"", repr(p))
    @test endswith(repr(p), ")")
    @test parse(ExtendedPlatform, triplet(p)) == p
    meta = Dict{String,String}()
    Artifacts.pack_platform!(meta, p)
    @test meta == Dict("libgfortran_version" => "5.0.0","arch" => "powerpc64le","libc" => "glibc","os" => "linux","cxxstring_abi" => "cxx03")

    p = ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5", cxxstring_abi=:cxx11)); microarchitecture="skylake_avx512", cuda="10.1", cuda_capability="52")
    @test p.p == Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5", cxxstring_abi=:cxx11))
    @test p.ext == Dict("microarchitecture" => "skylake_avx512","cuda_capability" => "52","cuda" => "10.1")
    @test BinaryPlatforms.platform_name(p) == "ExtendedPlatform"
    @test BinaryPlatforms.arch(p) == :powerpc64le
    @test BinaryPlatforms.libc(p) == :glibc
    @test BinaryPlatforms.call_abi(p) == nothing
    @test BinaryPlatforms.compiler_abi(p) == CompilerABI(libgfortran_version=v"5", cxxstring_abi=:cxx11)
    @test BinaryPlatforms.triplet(p) == "powerpc64le-linux-gnu-libgfortran5-cxx11-cuda+10.1-cuda_capability+52-microarchitecture+skylake_avx512"
    @test abi_agnostic(p) == Linux(:powerpc64le, libc=:glibc)
    @test aatriplet(p) == "powerpc64le-linux-gnu"
    @test replace_cxxstring_abi(p, :cxx11) == p
    @test replace_libgfortran_version(p, v"5") == p
    @test get_concrete_platform(p; compilers = [:c], preferred_gcc_version = v"5", preferred_llvm_version = v"9") == ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5", cxxstring_abi=:cxx11)); microarchitecture="skylake_avx512", cuda_capability="52", cuda="10.1")
    @test ExtendedPlatform(p; cuda="10.1", foo="bar") == ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5.0.0", cxxstring_abi=:cxx11)); microarchitecture="skylake_avx512", cuda_capability="52", cuda="10.1", foo="bar")
    @test ExtendedPlatform(p; foo="bar") == ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"5.0.0", cxxstring_abi=:cxx11)); microarchitecture="skylake_avx512", cuda_capability="52", cuda="10.1", foo="bar")
    @test_throws ErrorException ExtendedPlatform(p; cuda="10.1", cuda_capability="80")
    @test startswith(repr(p), "ExtendedPlatform(Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v\"5.0.0\", cxxstring_abi=:cxx11)); ")
    @test occursin("microarchitecture=\"skylake_avx512\"", repr(p))
    @test occursin("cuda=\"10.1\"", repr(p))
    @test occursin("cuda_capability=\"52\"", repr(p))
    @test endswith(repr(p), ")")
    @test parse(ExtendedPlatform, triplet(p)) == p
    meta = Dict{String,String}()
    Artifacts.pack_platform!(meta, p)
    @test meta == Dict("libgfortran_version" => "5.0.0","arch" => "powerpc64le","libc" => "glibc","os" => "linux","cxxstring_abi" => "cxx11")

    p = ExtendedPlatform(Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(; libstdcxx_version=v"3.4.24")); march="armv7l", cuda="11.1")
    @test p.p == Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(; libstdcxx_version=v"3.4.24"))
    @test p.ext == Dict("march" => "armv7l","cuda" => "11.1")
    @test BinaryPlatforms.platform_name(p) == "ExtendedPlatform"
    @test BinaryPlatforms.arch(p) == :armv7l
    @test BinaryPlatforms.libc(p) == :glibc
    @test BinaryPlatforms.call_abi(p) == :eabihf
    @test BinaryPlatforms.compiler_abi(p) == CompilerABI(libstdcxx_version=v"3.4.24")
    @test occursin(r"^arm(v7l)?-linux-gnueabihf-libstdcxx24-cuda\+11.1-march\+armv7l$", BinaryPlatforms.triplet(p))
    @test abi_agnostic(p) == Linux(:armv7l, libc=:glibc, call_abi=:eabihf)
    @test aatriplet(p) == "arm-linux-gnueabihf"
    @test replace_cxxstring_abi(p, :cxx11) == ExtendedPlatform(Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(; cxxstring_abi=:cxx11, libstdcxx_version=v"3.4.24")); march="armv7l", cuda="11.1")
    @test replace_libgfortran_version(p, v"4") == ExtendedPlatform(Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(; libgfortran_version=v"4", libstdcxx_version=v"3.4.24")); march="armv7l", cuda="11.1")
    @test get_concrete_platform(p; compilers = [:c], preferred_gcc_version = v"7", preferred_llvm_version = v"9") == ExtendedPlatform(Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(libgfortran_version=v"4.0.0", libstdcxx_version=v"3.4.24", cxxstring_abi=:cxx11)); march="armv7l", cuda="11.1")
    @test ExtendedPlatform(p; cuda="11.1", foo="bar") == ExtendedPlatform(Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(libstdcxx_version=v"3.4.24")); march="armv7l", cuda="11.1", foo="bar")
    @test ExtendedPlatform(p; foo="bar") == ExtendedPlatform(Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(libstdcxx_version=v"3.4.24")); march="armv7l", cuda="11.1", foo="bar")
    @test_throws ErrorException ExtendedPlatform(p; cuda="11.1", march="neon")
    @test startswith(repr(p), "ExtendedPlatform(Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(libstdcxx_version=v\"3.4.24\")); ")
    @test occursin("march=\"armv7l\"", repr(p))
    @test occursin("cuda=\"11.1\"", repr(p))
    @test endswith(repr(p), ")")
    @test parse(ExtendedPlatform, triplet(p)) == p
    meta = Dict{String,String}()
    Artifacts.pack_platform!(meta, p)
    @test meta == Dict("arch" => "armv7l","libc" => "glibc","march" => "armv7l","libstdcxx_version" => "3.4.24","os" => "linux")

    # Parse `"any"` as `AnyPlatform`
    @test tryparse(ExtendedPlatform, "any") == AnyPlatform()
    # AnyPlatform shouldn't be extended
    @test isnothing(tryparse(ExtendedPlatform, "any-march+avx"))
    # This is valid standard platform
    @test tryparse(ExtendedPlatform, "x86_64-unknown-freebsd11.1") == FreeBSD(:x86_64)
    # This string doesn't contain any platform at all
    @test isnothing(tryparse(ExtendedPlatform, "abcde"))
    # What comes before the first key-value pair is not a valid platform
    @test isnothing(tryparse(ExtendedPlatform, "armv7l-linux-musleabihf-this-is+not-valid"))
    # This string doesn't contain valid key-value pairs in the extra part
    @test_throws ArgumentError parse(ExtendedPlatform, "x86_64-linux-gnu-this+is-not-valid")

    @testset "base_platform" begin
        @test base_platform(Linux(:armv7l)) == Linux(:armv7l)
        @test base_platform(ExtendedPlatform(FreeBSD(:x86_64); march="avx")) == FreeBSD(:x86_64)
    end

    @testset "march" begin
        @test isnothing(march(Linux(:x86_64)))
        @test isnothing(march(AnyPlatform()))
        @test isnothing(march(ExtendedPlatform(Windows(:x86_64); cuda="9.2")))
        @test march(ExtendedPlatform(FreeBSD(:x86_64); march="avx512")) == "avx512"
    end

    @testset "Sys utilities" begin
        p = ExtendedPlatform(Linux(:x86_64); cuda="9.2")
        @test Sys.islinux(p)
        @test !Sys.isapple(p)
        @test !Sys.isbsd(p)
        @test !Sys.iswindows(p)
        p = ExtendedPlatform(FreeBSD(:x86_64); cuda="9.2")
        @test !Sys.islinux(p)
        @test !Sys.isapple(p)
        @test Sys.isbsd(p)
        @test !Sys.iswindows(p)
        p = ExtendedPlatform(MacOS(:x86_64); march="avx512")
        @test !Sys.islinux(p)
        @test Sys.isapple(p)
        @test Sys.isbsd(p)
        @test !Sys.iswindows(p)
        p = ExtendedPlatform(Windows(:x86_64); foo="bar")
        @test !Sys.islinux(p)
        @test !Sys.isapple(p)
        @test !Sys.isbsd(p)
        @test Sys.iswindows(p)
    end

    @testset "Platform matching" begin
        # Extending same platform
        @test !platforms_match(ExtendedPlatform(Linux(:i686; libc=:musl); cuda="9.2"), ExtendedPlatform(Linux(:i686; libc=:glibc); cuda="9.2"))
        @test platforms_match(ExtendedPlatform(Linux(:i686; libc=:musl); cuda="9.2"), ExtendedPlatform(Linux(:i686; libc=:musl); cuda="9.2"))
        @test platforms_match(ExtendedPlatform(Linux(:i686; libc=:musl); cuda="9.2"), ExtendedPlatform(Linux(:i686; libc=:musl); cuda="9.2", microarchitecture="avx"))
        @test !platforms_match(ExtendedPlatform(Linux(:i686; libc=:musl); cuda="9.1"), ExtendedPlatform(Linux(:i686; libc=:musl); cuda="9.2", microarchitecture="avx"))
        # Extending the same platform as the other one
        @test platforms_match(ExtendedPlatform(Linux(:powerpc64le; compiler_abi=CompilerABI(; libgfortran_version=v"5")); microarchitecture="skylake_avx512"), Linux(:powerpc64le))
        @test !platforms_match(ExtendedPlatform(Windows(:x86_64); microarchitecture="avx"), Windows(:i686))
        @test platforms_match(MacOS(:x86_64; compiler_abi=CompilerABI(; cxxstring_abi=:cxx11)), ExtendedPlatform(MacOS(:x86_64); microarchitecture="skylake"))
        @test !platforms_match(FreeBSD(:x86_64; compiler_abi=CompilerABI(; cxxstring_abi=:cxx03)), ExtendedPlatform(FreeBSD(:x86_64; compiler_abi=CompilerABI(; cxxstring_abi=:cxx11)); cuda="10.1"))
        # Extending a platform different from the other one
        @test !platforms_match(ExtendedPlatform(Linux(:i686); cuda="9.2"), MacOS(:x86_64))
        @test !platforms_match(Linux(:i686), ExtendedPlatform(Windows(:x86_64); cuda="9.2"))
        # Extending different platforms
        @test !platforms_match(ExtendedPlatform(Linux(:i686); cuda="10.1"), ExtendedPlatform(FreeBSD(:x86_64); cuda="11.1"))
    end
end

@testset "AnyPlatform" begin
    # Test some AnyPlatform properties
    @test triplet(AnyPlatform()) == "any"
    @test Pkg.BinaryPlatforms.platform_name(AnyPlatform()) == "AnyPlatform"
    @test abi_agnostic(AnyPlatform()) === AnyPlatform()
    @test arch(AnyPlatform()) == :x86_64
    @test repr(AnyPlatform()) == "AnyPlatform()"

    # In the build environment we want AnyPlatform to look like x86_64-linux-musl
    @test get_concrete_platform(AnyPlatform(); compilers = [:c], preferred_gcc_version = v"7", preferred_llvm_version = v"9") ==
        get_concrete_platform(Linux(:x86_64, libc=:musl); compilers = [:c], preferred_gcc_version = v"7", preferred_llvm_version = v"9")
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

    @test BinaryPlatforms.platform_dlext(ExtendedPlatform(Linux(:aarch64); march="thunderx2")) == "so"
    @test BinaryPlatforms.platform_dlext(ExtendedPlatform(FreeBSD(:x86_64); march="x86_64")) == "so"
    @test BinaryPlatforms.platform_dlext(ExtendedPlatform(MacOS(:x86_64); march="avx512")) == "dylib"
    @test BinaryPlatforms.platform_dlext(ExtendedPlatform(Windows(:i686); cuda="10.1")) == "dll"
end

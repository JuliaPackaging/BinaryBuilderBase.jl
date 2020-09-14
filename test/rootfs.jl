using Test
using Pkg.BinaryPlatforms
using BinaryBuilderBase
using BinaryBuilderBase: supported_microarchitectures

@testset "Expand platforms" begin
    # expand_gfortran_versions
    @test expand_gfortran_versions(Windows(:i686)) == [
        Windows(:i686, compiler_abi=CompilerABI(libgfortran_version=v"3.0.0")),
        Windows(:i686, compiler_abi=CompilerABI(libgfortran_version=v"4.0.0")),
        Windows(:i686, compiler_abi=CompilerABI(libgfortran_version=v"5.0.0")),
    ]
    @test expand_gfortran_versions([Windows(:i686), Windows(:x86_64)]) == [
        Windows(:i686, compiler_abi=CompilerABI(libgfortran_version=v"3.0.0")),
        Windows(:i686, compiler_abi=CompilerABI(libgfortran_version=v"4.0.0")),
        Windows(:i686, compiler_abi=CompilerABI(libgfortran_version=v"5.0.0")),
        Windows(:x86_64, compiler_abi=CompilerABI(libgfortran_version=v"3.0.0")),
        Windows(:x86_64, compiler_abi=CompilerABI(libgfortran_version=v"4.0.0")),
        Windows(:x86_64, compiler_abi=CompilerABI(libgfortran_version=v"5.0.0")),
    ]
    @test expand_gfortran_versions([FreeBSD(:x86_64; compiler_abi=CompilerABI(; libgfortran_version=v"3"))]) ==
        [FreeBSD(:x86_64; compiler_abi=CompilerABI(; libgfortran_version=v"3"))]

    # expand_cxxstring_abis
    @test expand_cxxstring_abis(Linux(:x86_64; libc=:musl)) == [
        Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(cxxstring_abi=:cxx03)),
        Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(cxxstring_abi=:cxx11)),
    ]
    @test expand_cxxstring_abis([FreeBSD(:x86_64), MacOS(:x86_64)]) == [
        FreeBSD(:x86_64),
        MacOS(:x86_64),
    ]
    @test expand_cxxstring_abis([FreeBSD(:x86_64), MacOS(:x86_64)]; skip_freebsd_macos=false) == [
        FreeBSD(:x86_64, compiler_abi=CompilerABI(cxxstring_abi=:cxx03)),
        FreeBSD(:x86_64, compiler_abi=CompilerABI(cxxstring_abi=:cxx11)),
        MacOS(:x86_64, compiler_abi=CompilerABI(cxxstring_abi=:cxx03)),
        MacOS(:x86_64, compiler_abi=CompilerABI(cxxstring_abi=:cxx11)),
    ]
    @test expand_cxxstring_abis([Linux(:i686; compiler_abi=CompilerABI(; cxxstring_abi=:cxx11))]) ==
        [Linux(:i686; compiler_abi=CompilerABI(; cxxstring_abi=:cxx11))]

    # `supported_microarchitectures` is only used inside
    # `expand_microarchitectures`, but it's better to have a unit test as well
    @test supported_microarchitectures(Linux(:i686)) == []
    @test supported_microarchitectures(Linux(:x86_64)) == ["avx", "avx2", "avx512", "x86_64"]
    @test supported_microarchitectures(Linux(:armv7l)) == ["armv7l", "neon", "vfp4"]
    # This extended platform doesn't specify a microarchitecture, so we can support all of them
    @test supported_microarchitectures(ExtendedPlatform(Linux(:aarch64); cuda="10.1")) == ["armv8", "carmel", "thunderx2"]
    @test supported_microarchitectures(Linux(:powerpc64le)) == []
    # This extended platform specifies a valid microarchitecture, so we support only the given architecture
    @test supported_microarchitectures(ExtendedPlatform(Linux(:x86_64); march="avx")) == ["avx"]
    @test supported_microarchitectures(AnyPlatform()) == []
    @test supported_microarchitectures(UnknownPlatform()) == []

    # expand_microarchitectures
    @test expand_microarchitectures([AnyPlatform()]) == [AnyPlatform()]
    @test expand_microarchitectures(ExtendedPlatform(Linux(:x86_64); cuda="10.1")) == [
        ExtendedPlatform(Linux(:x86_64, libc=:glibc); march="avx", cuda="10.1"),
        ExtendedPlatform(Linux(:x86_64, libc=:glibc); march="avx2", cuda="10.1"),
        ExtendedPlatform(Linux(:x86_64, libc=:glibc); march="avx512", cuda="10.1"),
        ExtendedPlatform(Linux(:x86_64, libc=:glibc); march="x86_64", cuda="10.1"),
    ]
    @test expand_microarchitectures(filter!(p -> p isa Linux && libc(p) == :glibc, supported_platforms())) == [
        Linux(:i686, libc=:glibc),
        ExtendedPlatform(Linux(:x86_64, libc=:glibc); march="avx"),
        ExtendedPlatform(Linux(:x86_64, libc=:glibc); march="avx2"),
        ExtendedPlatform(Linux(:x86_64, libc=:glibc); march="avx512"),
        ExtendedPlatform(Linux(:x86_64, libc=:glibc); march="x86_64"),
        ExtendedPlatform(Linux(:aarch64, libc=:glibc); march="armv8"),
        ExtendedPlatform(Linux(:aarch64, libc=:glibc); march="carmel"),
        ExtendedPlatform(Linux(:aarch64, libc=:glibc); march="thunderx2"),
        ExtendedPlatform(Linux(:armv7l, libc=:glibc, call_abi=:eabihf); march="armv7l"),
        ExtendedPlatform(Linux(:armv7l, libc=:glibc, call_abi=:eabihf); march="neon"),
        ExtendedPlatform(Linux(:armv7l, libc=:glibc, call_abi=:eabihf); march="vfp4"),
        Linux(:powerpc64le, libc=:glibc),
    ]
    @test expand_microarchitectures([ExtendedPlatform(Windows(:x86_64); cuda="10.1", march="avx")]) ==
        [ExtendedPlatform(Windows(:x86_64); march="avx", cuda="10.1")]

    # All of them together!
    @test all(in(expand_microarchitectures(expand_gfortran_versions(expand_cxxstring_abis(supported_platforms())))),
              expand_cxxstring_abis(expand_gfortran_versions(expand_microarchitectures(supported_platforms()))))
end

@testset "Compiler Shards" begin
    @test_throws ErrorException CompilerShard("GCCBootstrap", v"4", Linux(:x86_64), :invalid_archive_type)

    @testset "GCC ABI matching" begin
        # Preferred libgfortran version and C++ string ABI
        platform = FreeBSD(:x86_64)
        shard = CompilerShard("GCCBootstrap", v"4.8.5", Linux(:x86_64, libc=:musl), :squashfs, target = platform)
        @test preferred_libgfortran_version(platform, shard) == v"3"
        @test preferred_cxxstring_abi(platform, shard) == :cxx03
        shard = CompilerShard("GCCBootstrap", v"5.2.0", Linux(:x86_64, libc=:musl), :squashfs, target = platform)
        @test preferred_libgfortran_version(platform, shard) == v"3"
        @test preferred_cxxstring_abi(platform, shard) == :cxx11
        shard = CompilerShard("GCCBootstrap", v"7.1.0", Linux(:x86_64, libc=:musl), :squashfs, target = platform)
        @test preferred_libgfortran_version(platform, shard) == v"4"
        @test preferred_cxxstring_abi(platform, shard) == :cxx11
        shard = CompilerShard("GCCBootstrap", v"9.1.0", Linux(:x86_64, libc=:musl), :squashfs, target = platform)
        @test preferred_libgfortran_version(platform, shard) == v"5"
        @test preferred_cxxstring_abi(platform, shard) == :cxx11
        shard = CompilerShard("LLVMBootstrap", v"4.8.5", Linux(:x86_64, libc=:musl), :squashfs)
        @test_throws ErrorException preferred_libgfortran_version(platform, shard)
        @test_throws ErrorException preferred_cxxstring_abi(platform, shard)
        platform = Linux(:x86_64, libc=:musl)
        shard = CompilerShard("GCCBootstrap", v"4.8.5", Linux(:x86_64, libc=:musl), :squashfs, target = MacOS(:x86_64))
        @test_throws ErrorException preferred_libgfortran_version(platform, shard)
        shard = CompilerShard("GCCBootstrap", v"4.8.5", Linux(:x86_64, libc=:musl), :squashfs, target = Linux(:x86_64, libc=:glibc))
        @test_throws ErrorException preferred_cxxstring_abi(platform, shard)
        shard = CompilerShard("GCCBootstrap", v"1.2.3", Linux(:x86_64, libc=:musl), :squashfs, target = Windows(:x86_64))
        @test_throws ErrorException preferred_cxxstring_abi(platform, shard)
        @test_throws ErrorException preferred_libgfortran_version(platform, shard)

        # With no constraints, we should get them all back
        @test gcc_version(Linux(:x86_64), available_gcc_builds) == getversion.(available_gcc_builds)

        # libgfortran v3 and libstdcxx 22 restrict us to only v4.8, v5.2 and v6.1
        cabi = CompilerABI(;libgfortran_version=v"3", libstdcxx_version=v"3.4.22")
        p = Linux(:x86_64; compiler_abi=cabi)
        @test gcc_version(p, available_gcc_builds) == [v"4.8.5", v"5.2.0", v"6.1.0"]
        ep = ExtendedPlatform(p; march="avx")
        @test gcc_version(ep, available_gcc_builds) == [v"5.2.0", v"6.1.0"]

        # Adding `:cxx11` eliminates `v"4.X"`:
        cabi = CompilerABI(cabi; cxxstring_abi=:cxx11)
        p = Linux(:x86_64; compiler_abi=cabi)
        @test gcc_version(p, available_gcc_builds) == [v"5.2.0", v"6.1.0"]
        ep = ExtendedPlatform(p; march="avx512")
        @test gcc_version(ep, available_gcc_builds) == [v"6.1.0"]

        # Just libgfortran v3 allows GCC 6 as well though
        cabi = CompilerABI(;libgfortran_version=v"3")
        p = Linux(:x86_64; compiler_abi=cabi)
        @test gcc_version(p, available_gcc_builds) == [v"4.8.5", v"5.2.0", v"6.1.0"]

        # Test libgfortran version v4, then splitting on libstdcxx_version:
        cabi = CompilerABI(;libgfortran_version=v"4")
        p = Linux(:x86_64; compiler_abi=cabi)
        @test gcc_version(p, available_gcc_builds) == [v"7.1.0"]
        cabi = CompilerABI(cabi; libstdcxx_version=v"3.4.23")
        p = Linux(:x86_64; compiler_abi=cabi)
        @test gcc_version(p, available_gcc_builds) == [v"7.1.0"]
        ep = ExtendedPlatform(Linux(:aarch64; compiler_abi=cabi); march="thunderx2")
        @test gcc_version(ep, available_gcc_builds) == [v"7.1.0"]

        ep = ExtendedPlatform(Linux(:armv7l); march="neon")
        @test gcc_version(ep, available_gcc_builds) == [v"8.1.0", v"9.1.0", v"11.0.0-iains"]
    end

    @testset "Compiler wrappers" begin
        platform = Linux(:x86_64, libc=:musl)
        mktempdir() do bin_path
            generate_compiler_wrappers!(platform; bin_path = bin_path)
            # Make sure the C++ string ABI is not set
            @test !occursin("-D_GLIBCXX_USE_CXX11_ABI", read(joinpath(bin_path, "gcc"), String))
            # Make sure gfortran doesn't uses ccache when BinaryBuilderBase.use_ccache is true
            BinaryBuilderBase.use_ccache && @test !occursin("ccache", read(joinpath(bin_path, "gfortran"), String))
        end
        platform = Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(cxxstring_abi=:cxx03))
        mktempdir() do bin_path
            generate_compiler_wrappers!(platform; bin_path = bin_path)
            gcc = read(joinpath(bin_path, "gcc"), String)
            # Make sure the C++ string ABI is set as expected
            @test occursin("-D_GLIBCXX_USE_CXX11_ABI=0", gcc)
            # Make sure the unsafe flags check is there
            @test occursin("You used one or more of the unsafe flags", gcc)
        end
        platform = Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(cxxstring_abi=:cxx11))
        mktempdir() do bin_path
            generate_compiler_wrappers!(platform; bin_path = bin_path, allow_unsafe_flags = true)
            gcc = read(joinpath(bin_path, "gcc"), String)
            # Make sure the C++ string ABI is set as expected
            @test occursin("-D_GLIBCXX_USE_CXX11_ABI=1", gcc)
            # Make sure the unsafe flags check is not there in this case
            @test !occursin("You used one or more of the unsafe flags", gcc)
        end
        platform = FreeBSD(:x86_64)
        mktempdir() do bin_path
            generate_compiler_wrappers!(platform; bin_path = bin_path, compilers = [:c, :rust, :go])
            clang = read(joinpath(bin_path, "clang"), String)
            # Check link flags
            @test occursin("-L/opt/$(triplet(platform))/$(triplet(platform))/lib", clang)
            @test occursin("fuse-ld=$(triplet(platform))", clang)
            # Other compilers
            @test occursin("GOOS=\"freebsd\"", read(joinpath(bin_path, "go"), String))
            @test occursin("--target=x86_64-unknown-freebsd", read(joinpath(bin_path, "rustc"), String))
        end
        platform      = Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(cxxstring_abi=:cxx03))
        host_platform = Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(cxxstring_abi=:cxx11))
        mktempdir() do bin_path
            @test_throws ErrorException generate_compiler_wrappers!(platform; bin_path = bin_path, host_platform = host_platform)
        end
        platform      = Linux(:x86_64, libc=:musl)
        host_platform = Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(cxxstring_abi=:cxx03))
        mktempdir() do bin_path
            @test_throws ErrorException generate_compiler_wrappers!(platform; bin_path = bin_path, host_platform = host_platform)
        end
    end
end

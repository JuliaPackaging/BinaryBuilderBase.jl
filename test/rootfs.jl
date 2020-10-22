using Test
using Base.BinaryPlatforms
using BinaryBuilderBase

@testset "Expand platforms" begin
    # expand_gfortran_versions
    @test expand_gfortran_versions(Platform("i686", "windows")) == [
        Platform("i686", "windows"; libgfortran_version=v"3"),
        Platform("i686", "windows"; libgfortran_version=v"4"),
        Platform("i686", "windows"; libgfortran_version=v"5"),
    ]
    @test expand_gfortran_versions([Platform("i686", "windows"), Platform("x86_64", "windows")]) == [
        Platform("i686", "windows"; libgfortran_version=v"3"),
        Platform("i686", "windows"; libgfortran_version=v"4"),
        Platform("i686", "windows"; libgfortran_version=v"5"),
        Platform("x86_64", "windows"; libgfortran_version=v"3"),
        Platform("x86_64", "windows"; libgfortran_version=v"4"),
        Platform("x86_64", "windows"; libgfortran_version=v"5"),
    ]
    @test expand_gfortran_versions([Platform("x86_64", "freebsd"; libgfortran_version=v"3")]) ==
        [Platform("x86_64", "freebsd"; libgfortran_version=v"3")]
    @test expand_gfortran_versions([Platform("x86_64", "macos"), Platform("aarch64", "macos")]) == [
        Platform("x86_64",  "macos"; libgfortran_version=v"3"),
        Platform("x86_64",  "macos"; libgfortran_version=v"4"),
        Platform("x86_64",  "macos"; libgfortran_version=v"5"),
        Platform("aarch64", "macos"; libgfortran_version=v"5"),
    ]

    # expand_cxxstring_abis
    @test expand_cxxstring_abis(Platform("x86_64", "linux"; libc="musl")) == [
        Platform("x86_64", "linux", libc="musl", cxxstring_abi="cxx03"),
        Platform("x86_64", "linux", libc="musl", cxxstring_abi="cxx11"),
    ]
    @test expand_cxxstring_abis([Platform("x86_64", "freebsd"), Platform("x86_64", "macos")]) == [
        Platform("x86_64", "freebsd"),
        Platform("x86_64", "macos"),
    ]
    @test expand_cxxstring_abis([Platform("x86_64", "freebsd"), Platform("x86_64", "macos")]; skip=_->false) == [
        Platform("x86_64", "freebsd"; cxxstring_abi="cxx03"),
        Platform("x86_64", "freebsd"; cxxstring_abi="cxx11"),
        Platform("x86_64", "macos"; cxxstring_abi="cxx03"),
        Platform("x86_64", "macos"; cxxstring_abi="cxx11"),
    ]
    @test expand_cxxstring_abis([Platform("x86_64", "freebsd"), Platform("x86_64", "linux")]; skip=Sys.islinux) == [
        Platform("x86_64", "freebsd"; cxxstring_abi="cxx03"),
        Platform("x86_64", "freebsd"; cxxstring_abi="cxx11"),
        Platform("x86_64", "linux"),
    ]
    @test expand_cxxstring_abis([Platform("i686", "linux"; cxxstring_abi="cxx11")]) ==
        [Platform("i686", "linux"; cxxstring_abi="cxx11")]

    # expand_microarchitectures
    @test expand_microarchitectures([AnyPlatform()]) == [AnyPlatform()]
    @test sort(expand_microarchitectures(Platform("x86_64", "linux"; cuda="10.1")), by=triplet) == [
        Platform("x86_64", "linux"; libc="glibc", march="avx", cuda="10.1"),
        Platform("x86_64", "linux"; libc="glibc", march="avx2", cuda="10.1"),
        Platform("x86_64", "linux"; libc="glibc", march="avx512", cuda="10.1"),
        Platform("x86_64", "linux"; libc="glibc", march="x86_64", cuda="10.1"),
    ]
    @test sort(expand_microarchitectures(filter!(p -> Sys.islinux(p) && libc(p) == "glibc", supported_platforms())), by=triplet) == [
        Platform("aarch64", "linux"; libc="glibc", march="armv8_0"),
        Platform("aarch64", "linux"; libc="glibc", march="armv8_1"),
        Platform("aarch64", "linux"; libc="glibc", march="armv8_2_crypto"),
        Platform("aarch64", "linux"; libc="glibc", march="armv8_4_crypto_sve"),
        # Platform("armv6l", "linux"; libc="glibc", call_abi="eabihf", march="arm1176jzfs"),
        Platform("armv7l", "linux"; libc="glibc", call_abi="eabihf", march="armv7l"),
        Platform("armv7l", "linux"; libc="glibc", call_abi="eabihf", march="neonvfpv4"),
        Platform("i686", "linux"; libc="glibc", march="i686"),
        Platform("i686", "linux"; libc="glibc", march="prescott"),
        Platform("powerpc64le", "linux"; libc="glibc", march="power8"),
        Platform("x86_64", "linux"; libc="glibc", march="avx"),
        Platform("x86_64", "linux"; libc="glibc", march="avx2"),
        Platform("x86_64", "linux"; libc="glibc", march="avx512"),
        Platform("x86_64", "linux"; libc="glibc", march="x86_64"),
    ]
    @test expand_microarchitectures([Platform("x86_64", "windows"; march="avx", cuda="10.1")]) ==
        [Platform("x86_64", "windows"; march="avx", cuda="10.1")]

    # All of them together!
    @test all(in(expand_microarchitectures(expand_gfortran_versions(expand_cxxstring_abis(supported_platforms())))),
                 expand_cxxstring_abis(expand_gfortran_versions(expand_microarchitectures(supported_platforms()))))
end

@testset "Compiler Shards" begin
    @test_throws ErrorException CompilerShard("GCCBootstrap", v"4", Platform("x86_64", "linux"), :invalid_archive_type)

    @testset "GCC ABI matching" begin
        # Preferred libgfortran version and C++ string ABI
        platform = Platform("x86_64", "freebsd")
        shard = CompilerShard("GCCBootstrap", v"4.8.5", Platform("x86_64", "linux"; libc="musl"), :squashfs, target = platform)
        @test preferred_libgfortran_version(platform, shard) == v"3"
        @test preferred_cxxstring_abi(platform, shard) == "cxx03"
        shard = CompilerShard("GCCBootstrap", v"5.2.0", Platform("x86_64", "linux"; libc="musl"), :squashfs, target = platform)
        @test preferred_libgfortran_version(platform, shard) == v"3"
        @test preferred_cxxstring_abi(platform, shard) == "cxx11"
        shard = CompilerShard("GCCBootstrap", v"7.1.0", Platform("x86_64", "linux"; libc="musl"), :squashfs, target = platform)
        @test preferred_libgfortran_version(platform, shard) == v"4"
        @test preferred_cxxstring_abi(platform, shard) == "cxx11"
        shard = CompilerShard("GCCBootstrap", v"9.1.0", Platform("x86_64", "linux"; libc="musl"), :squashfs, target = platform)
        @test preferred_libgfortran_version(platform, shard) == v"5"
        @test preferred_cxxstring_abi(platform, shard) == "cxx11"
        shard = CompilerShard("LLVMBootstrap", v"4.8.5", Platform("x86_64", "linux"; libc="musl"), :squashfs)
        @test_throws ErrorException preferred_libgfortran_version(platform, shard)
        @test_throws ErrorException preferred_cxxstring_abi(platform, shard)
        platform = Platform("x86_64", "linux"; libc="musl")
        shard = CompilerShard("GCCBootstrap", v"4.8.5", Platform("x86_64", "linux"; libc="musl"), :squashfs, target = Platform("x86_64", "macos"))
        @test_throws ErrorException preferred_libgfortran_version(platform, shard)
        shard = CompilerShard("GCCBootstrap", v"4.8.5", Platform("x86_64", "linux"; libc="musl"), :squashfs, target = Platform("x86_64", "linux"; libc="glibc"))
        @test_throws ErrorException preferred_cxxstring_abi(platform, shard)
        shard = CompilerShard("GCCBootstrap", v"1.2.3", Platform("x86_64", "linux"; libc="musl"), :squashfs, target = Platform("x86_64", "windows"))
        @test_throws ErrorException preferred_cxxstring_abi(platform, shard)
        @test_throws ErrorException preferred_libgfortran_version(platform, shard)

        # With no constraints, we should get them all back
        @test gcc_version(Platform("x86_64", "linux"), available_gcc_builds) == getversion.(available_gcc_builds)

        # libgfortran v3 and libstdcxx 22 restrict us to only v4.8, v5.2 and v6.1
        p = Platform("x86_64", "linux"; libgfortran_version=v"3", libstdcxx_version=v"3.4.22")
        @test gcc_version(p, available_gcc_builds) == [v"4.8.5", v"5.2.0", v"6.1.0"]
        p["march"] = "avx"
        @test gcc_version(p, available_gcc_builds) == [v"5.2.0", v"6.1.0"]

        # Adding `"cxx11"` eliminates `v"4.X"`:
        p = Platform("x86_64", "linux"; libgfortran_version=v"3", cxxstring_abi="cxx11")
        @test gcc_version(p, available_gcc_builds) == [v"5.2.0", v"6.1.0"]
        p["march"] = "avx512"
        @test gcc_version(p, available_gcc_builds) == [v"6.1.0"]

        # Just libgfortran v3 allows GCC 6 as well though
        p = Platform("x86_64", "linux"; libgfortran_version=v"3")
        @test gcc_version(p, available_gcc_builds) == [v"4.8.5", v"5.2.0", v"6.1.0"]

        # Test libgfortran version v4, then splitting on libstdcxx_version:
        p = Platform("x86_64", "linux"; libgfortran_version=v"4")
        @test gcc_version(p, available_gcc_builds) == [v"7.1.0"]
        p = Platform("x86_64", "linux"; libgfortran_version=v"4", libstdcxx_version=v"3.4.23")
        @test gcc_version(p, available_gcc_builds) == [v"7.1.0"]
        p = Platform("aarch64", "linux"; libgfortran_version=v"4", libstdcxx_version=v"3.4.23", march="thunderx2")
        @test gcc_version(p, available_gcc_builds) == [v"7.1.0"]

        p = Platform("armv7l", "linux"; march="neonvfpv4")
        @test gcc_version(p, available_gcc_builds) == [v"5.2.0", v"6.1.0", v"7.1.0", v"8.1.0", v"9.1.0", v"11.0.0-iains"]
    end

    @testset "Compiler wrappers" begin
        platform = Platform("x86_64", "linux"; libc="musl")
        mktempdir() do bin_path
            generate_compiler_wrappers!(platform; bin_path = bin_path)
            # Make sure the C++ string ABI is not set
            @test !occursin("-D_GLIBCXX_USE_CXX11_ABI", read(joinpath(bin_path, "gcc"), String))
            # Make sure gfortran doesn't uses ccache when BinaryBuilderBase.use_ccache is true
            BinaryBuilderBase.use_ccache && @test !occursin("ccache", read(joinpath(bin_path, "gfortran"), String))
        end
        platform = Platform("x86_64", "linux"; libc="musl", cxxstring_abi="cxx03")
        mktempdir() do bin_path
            generate_compiler_wrappers!(platform; bin_path = bin_path)
            gcc = read(joinpath(bin_path, "gcc"), String)
            # Make sure the C++ string ABI is set as expected
            @test occursin("-D_GLIBCXX_USE_CXX11_ABI=0", gcc)
            # Make sure the unsafe flags check is there
            @test occursin("You used one or more of the unsafe flags", gcc)
        end
        platform = Platform("x86_64", "linux"; libc="musl", cxxstring_abi="cxx11")
        mktempdir() do bin_path
            generate_compiler_wrappers!(platform; bin_path = bin_path, allow_unsafe_flags = true)
            gcc = read(joinpath(bin_path, "gcc"), String)
            # Make sure the C++ string ABI is set as expected
            @test occursin("-D_GLIBCXX_USE_CXX11_ABI=1", gcc)
            # Make sure the unsafe flags check is not there in this case
            @test !occursin("You used one or more of the unsafe flags", gcc)
        end
        platform = Platform("x86_64", "freebsd")
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
        platform      = Platform("x86_64", "linux"; libc="musl", cxxstring_abi="cxx03")
        host_platform = Platform("x86_64", "linux"; libc="musl", cxxstring_abi="cxx11")
        mktempdir() do bin_path
            @test_throws ErrorException generate_compiler_wrappers!(platform; bin_path = bin_path, host_platform = host_platform)
        end
        platform      = Platform("x86_64", "linux"; libc="musl")
        host_platform = Platform("x86_64", "linux"; libc="musl", cxxstring_abi="cxx03")
        mktempdir() do bin_path
            @test_throws ErrorException generate_compiler_wrappers!(platform; bin_path = bin_path, host_platform = host_platform)
        end
    end
end

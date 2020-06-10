using Test
using Pkg.BinaryPlatforms
using BinaryBuilderBase

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
        @test gcc_version(CompilerABI(), available_gcc_builds) == getversion.(available_gcc_builds)

        # libgfortran v3 and libstdcxx 22 restrict us to only v4.8, v5.2 and v6.1
        cabi = CompilerABI(;libgfortran_version=v"3", libstdcxx_version=v"3.4.22")
        @test gcc_version(cabi, available_gcc_builds) == [v"4.8.5", v"5.2.0", v"6.1.0"]

        # Adding `:cxx11` eliminates `v"4.X"`:
        cabi = CompilerABI(cabi; cxxstring_abi=:cxx11)
        @test gcc_version(cabi, available_gcc_builds) == [v"5.2.0", v"6.1.0"]

        # Just libgfortran v3 allows GCC 6 as well though
        cabi = CompilerABI(;libgfortran_version=v"3")
        @test gcc_version(cabi, available_gcc_builds) == [v"4.8.5", v"5.2.0", v"6.1.0"]

        # Test libgfortran version v4, then splitting on libstdcxx_version:
        cabi = CompilerABI(;libgfortran_version=v"4")
        @test gcc_version(cabi, available_gcc_builds) == [v"7.1.0"]
        cabi = CompilerABI(cabi; libstdcxx_version=v"3.4.23")
        @test gcc_version(cabi, available_gcc_builds) == [v"7.1.0"]
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

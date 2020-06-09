## Basic tests for simple utilities within BB
using BinaryBuilderBase, Test, Pkg
using BinaryBuilderBase: preferred_runner, resolve_jlls, CompilerShard, preferred_libgfortran_version, preferred_cxxstring_abi, gcc_version, available_gcc_builds, getversion, generate_compiler_wrappers!, getpkg

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


@testset "Products" begin
    lp = LibraryProduct("libfakechroot", :libfakechroot, "lib/fakechroot")
    @test lp.libnames ==  ["libfakechroot"]
    @test lp.dir_paths == ["lib/fakechroot"]
    ep = ExecutableProduct("fooify", :fooify, "bin/foo_inc")
    @test ep.binnames ==  ["fooify"]

    @test_throws ErrorException LibraryProduct("sin", :sin)
    @test_throws ErrorException ExecutableProduct("convert", :convert)
    @test_throws ErrorException FileProduct("open", :open)

    # Test sorting of products....
    @test sort([LibraryProduct("libbar", :libbar), ExecutableProduct("foo", :foo), FrameworkProduct("buzz", :buzz)]) ==
        [FrameworkProduct("buzz", :buzz), ExecutableProduct("foo", :foo), LibraryProduct("libbar", :libbar)]
    # ...and products info
    p1 = LibraryProduct(["libchafa"], :libchafa, ) => Dict("soname" => "libchafa.so.0","path" => "lib/libchafa.so")
    p2 = ExecutableProduct(["chafa"], :chafa, ) => Dict("path" => "bin/chafa")
    products_info = Dict{Product,Any}(p1, p2)
    @test sort(products_info) == [p2, p1]
end

# Are we using docker? If so, test that the docker runner works...
@testset "Runner utilities" begin
    # Test that is_ecryptfs works for something we're certain isn't encrypted
    if isdir("/proc")
        isecfs = (false, "/proc/")
        @test BinaryBuilderBase.is_ecryptfs("/proc"; verbose=true) == isecfs
        @test BinaryBuilderBase.is_ecryptfs("/proc/"; verbose=true) == isecfs
        @test BinaryBuilderBase.is_ecryptfs("/proc/not_a_file"; verbose=true) == isecfs
    else
        @test BinaryBuilderBase.is_ecryptfs("/proc"; verbose=true) == (false, "/proc")
        @test BinaryBuilderBase.is_ecryptfs("/proc/"; verbose=true) == (false, "/proc/")
        @test BinaryBuilderBase.is_ecryptfs("/proc/not_a_file"; verbose=true) == (false, "/proc/not_a_file")
    end

    if isa(preferred_runner(), BinaryBuilderBase.DockerRunner)
        @testset "Docker image importing" begin
            # First, delete the docker image, in case it already existed
            BinaryBuilderBase.delete_docker_image()

            # Next, import it and ensure that doesn't throw
            rootfs = first(BinaryBuilderBase.choose_shards(platform))
            mktempdir() do dir
                @test BinaryBuilderBase.import_docker_image(rootfs, dir; verbose=true) === nothing
            end

            # Test that deleting the docker image suceeds, now that we know
            # it exists
            @test BinaryBuilderBase.delete_docker_image()
        end
    end

    @testset "hello world" begin
        mktempdir() do dir
            ur = preferred_runner()(dir; platform=Linux(:x86_64; libc=:musl))
            iobuff = IOBuffer()
            @test run(ur, `/bin/bash -c "echo test"`, iobuff)
            seek(iobuff, 0)
            # Test that we get the output we expect (e.g. the second line is `test`)
            @test split(String(read(iobuff)), "\n")[2] == "test"
        end
    end
end


@testset "Tree symlinking" begin
    # Make sure symlink_tree works well with symlinks
    mktempdir() do tmpdir
        # Create fake source directory
        srcdir = joinpath(tmpdir, "src")
        mkdir(srcdir)

        mkdir(joinpath(srcdir, "dir"))
        open(joinpath(srcdir, "dir", "fileA"), "w") do io
            println(io, "fileA")
        end
        open(joinpath(srcdir, "dir", "fileB"), "w") do io
            println(io, "fileB")
        end
        symlink(joinpath("dir", "fileA"), joinpath(srcdir, "sym_fileA"))
        symlink("dir", joinpath(srcdir, "sym_dir"))

        dstdir = joinpath(tmpdir, "dst")

        # Set up a symlink tree inside of dstdir
        BinaryBuilderBase.symlink_tree(srcdir, dstdir)

        @test isdir(dstdir)
        @test isdir(joinpath(dstdir, "dir"))
        @test islink(joinpath(dstdir, "sym_dir"))
        @test islink(joinpath(dstdir, "sym_fileA"))
        @test islink(joinpath(dstdir, "dir", "fileA"))
        @test islink(joinpath(dstdir, "dir", "fileB"))

        @test readlink(joinpath(dstdir, "sym_dir")) == "dir"
        @test readlink(joinpath(dstdir, "sym_fileA")) == joinpath("dir", "fileA")

        @test String(read(joinpath(dstdir, "dir", "fileA"))) == "fileA\n"
        @test String(read(joinpath(dstdir, "dir", "fileB"))) == "fileB\n"
        @test String(read(joinpath(dstdir, "sym_fileA"))) == "fileA\n"
        @test String(read(joinpath(dstdir, "sym_dir", "fileB"))) == "fileB\n"

        # Create some files in `dstdir`, then unsymlink and see what happens:
        open(joinpath(dstdir, "dir", "fileC"), "w") do io
            println(io, "fileC")
        end
        symlink(joinpath("dir", "fileB"), joinpath(dstdir, "sym_fileB"))
        symlink(joinpath("dir", "fileC"), joinpath(dstdir, "sym_fileC"))
        symlink("dir", joinpath(dstdir, "sym_dir2"))

        BinaryBuilderBase.unsymlink_tree(srcdir, dstdir)

        @test isdir(dstdir)
        @test isdir(joinpath(dstdir, "dir"))
        @test !islink(joinpath(dstdir, "sym_dir"))
        @test !islink(joinpath(dstdir, "sym_fileA"))
        @test !isfile(joinpath(dstdir, "dir", "fileA"))
        @test !isfile(joinpath(dstdir, "dir", "fileB"))
        @test isfile(joinpath(dstdir, "dir", "fileC"))
        @test islink(joinpath(dstdir, "sym_dir2"))
        @test islink(joinpath(dstdir, "sym_fileB"))
        @test islink(joinpath(dstdir, "sym_fileC"))

        @test String(read(joinpath(dstdir, "dir", "fileC"))) == "fileC\n"
        @test String(read(joinpath(dstdir, "sym_fileC"))) == "fileC\n"
        @test_throws Base.IOError realpath(joinpath(dstdir, "sym_fileB"))
    end
end

@testset "resolve_jlls" begin
    # Deps given by name::String
    dependencies = ["OpenSSL_jll",]
    @test_logs (:warn, r"use Dependency instead") begin
        truefalse, resolved_deps = resolve_jlls(dependencies)
        @test truefalse
        @test all(x->getpkg(x).uuid !== nothing, resolved_deps)
    end
    # Deps given by name::PackageSpec
    @test_logs (:warn, r"use Dependency instead") begin
        dependencies = [PackageSpec(name="OpenSSL_jll"),]
        truefalse, resolved_deps = resolve_jlls(dependencies)
        @test truefalse
        @test all(x->getpkg(x).uuid !== nothing, resolved_deps)
    end
    # Deps given by (name,uuid)::PackageSpec
    dependencies = [Dependency(PackageSpec(name="OpenSSL_jll", uuid="458c3c95-2e84-50aa-8efc-19380b2a3a95")),]
    truefalse, resolved_deps = resolve_jlls(dependencies)
    @test truefalse
    @test all(x->getpkg(x).uuid !== nothing, resolved_deps)
    # Deps given by combination of name::String, name::PackageSpec and (name,uuid)::PackageSpec
    dependencies = [
        Dependency("Zlib_jll"),
        Dependency(PackageSpec(name="Bzip2_jll")),
        Dependency(PackageSpec(name="OpenSSL_jll", uuid="458c3c95-2e84-50aa-8efc-19380b2a3a95")),
    ]
    truefalse, resolved_deps = resolve_jlls(dependencies)
    @test truefalse
    @test all(x->getpkg(x).uuid !== nothing, resolved_deps)
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

@testset "Dlopen flags" begin
    lp = LibraryProduct("libfoo2", :libfoo2; dlopen_flags=[:RTLD_GLOBAL, :RTLD_NOLOAD])
    @test lp.dlopen_flags == [:RTLD_GLOBAL, :RTLD_NOLOAD]
    fp = FrameworkProduct("libfoo2", :libfoo2; dlopen_flags=[:RTLD_GLOBAL, :RTLD_NOLOAD])
    @test fp.libraryproduct.dlopen_flags == [:RTLD_GLOBAL, :RTLD_NOLOAD]
    for p in (lp, fp)
        flag_str = BinaryBuilderBase.dlopen_flags_str(p)
        @test flag_str == ", RTLD_GLOBAL | RTLD_NOLOAD"
        @test eval(Meta.parse(flag_str[3:end])) == (RTLD_NOLOAD | RTLD_GLOBAL)
    end
end

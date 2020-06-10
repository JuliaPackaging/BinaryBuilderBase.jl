## Basic tests for simple utilities within BB
using BinaryBuilderBase, Test, Pkg
using BinaryBuilderBase: preferred_runner, resolve_jlls, CompilerShard, preferred_libgfortran_version, preferred_cxxstring_abi, gcc_version, available_gcc_builds, getversion, generate_compiler_wrappers!, getpkg, abi_agnostic, template

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

@testset "Prefix" begin
    mktempdir() do temp_dir
        prefix = Prefix(temp_dir)

        # Test that it's taking the absolute path
        @test prefix.path == abspath(temp_dir)

        # Test that `bindir()`, `libdirs()` and `includedir()` all work
        for dir in unique([bindir(prefix), libdirs(prefix)..., includedir(prefix)])
            @test !isdir(dir)
            mkpath(dir)
        end

        # Create a little script within the bindir to ensure we can run it
        ppt_path = joinpath(bindir(prefix), "prefix_path_test.sh")
        open(ppt_path, "w") do f
            write(f, "#!/bin/sh\n")
            write(f, "echo yolo\n")
        end
        chmod(ppt_path, 0o775)

        # These tests are taken from BinaryProvider, but here we don't have
        # withenv.  Do we have anything similar?
        #
        # # Test that our `withenv()` stuff works.  :D
        # withenv(prefix) do
        #     @test startswith(ENV["PATH"], bindir(prefix))

        #     if !Sys.iswindows()
        #         envname = Sys.isapple() ? "DYLD_FALLBACK_LIBRARY_PATH" : "LD_LIBRARY_PATH"
        #         @test startswith(ENV[envname], last(libdirs(prefix)))
        #         private_libdir = abspath(joinpath(Sys.BINDIR, Base.PRIVATE_LIBDIR))
        #         @test endswith(ENV[envname], private_libdir)

        #         # Test we can run the script we dropped within this prefix.
        #         # Once again, something about Windows | busybox | Julia won't
        #         # pick this up even though the path clearly points to the file.
        #         @test success(`$sh $(ppt_path)`)
        #         @test success(`$sh -c prefix_path_test.sh`)
        #     end
        # end

        # Test that we can control libdirs() via platform arguments
        @test first(libdirs(prefix, Linux(:x86_64))) == joinpath(prefix, "lib64")
        @test last(libdirs(prefix, Linux(:x86_64))) == joinpath(prefix, "lib")
        @test last(libdirs(prefix, Windows(:x86_64))) == joinpath(prefix, "bin")
    end
end

@testset "Products" begin
    @test template(raw"$libdir/foo-$arch/$nbits/bar-$target", Windows(:x86_64)) ==
        "bin/foo-x86_64/64/bar-x86_64-w64-mingw32"
    @test template(raw"$target/$nbits/$arch/$libdir", Linux(:x86_64; libc = :musl)) ==
        "x86_64-linux-musl/64/x86_64/lib"

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

    temp_prefix() do prefix
        # Test that basic satisfication is not guaranteed
        e_path = joinpath(bindir(prefix), "fooifier")
        l_path = joinpath(last(libdirs(prefix)), "libfoo.$(Libdl.dlext)")
        e = ExecutableProduct("fooifier", :fooifier)
        ef = FileProduct(joinpath("bin", "fooifier"), :fooifier)
        l = LibraryProduct("libfoo", :libfoo)
        lf = FileProduct(l_path, :libfoo)

        @test @test_logs (:info, r"does not exist") !satisfied(e, prefix; verbose=true)
        @test @test_logs (:info, r"not found") !satisfied(ef, prefix; verbose=true)
        @test @test_logs (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true)
        @test @test_logs (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true, isolate=true)
        @test @test_logs (:info, r"^FileProduct .* not found") !satisfied(lf, prefix; verbose=true)

        # Test that simply creating a file that is not executable doesn't
        # satisfy an Executable Product (and say it's on Linux so it doesn't
        # complain about the lack of an .exe extension)
        mkpath(bindir(prefix))
        touch(e_path)
        @test @test_logs (:info, r"^FileProduct .* found at") satisfied(ef, prefix; verbose=true)
        @static if !Sys.iswindows()
            # Windows doesn't care about executable bit, grumble grumble
            @test @test_logs (:info, r"is not executable") (:info, r"does not exist") !satisfied(e, prefix; verbose=true, platform=Linux(:x86_64))
        end

        # Make it executable and ensure this does satisfy the Executable
        chmod(e_path, 0o777)
        @test @test_logs (:info, r"matches our search criteria") satisfied(e, prefix; verbose=true, platform=Linux(:x86_64))

        # Remove it and add a `$(path).exe` version to check again, this
        # time saying it's a Windows executable
        Base.rm(e_path; force=true)
        touch("$(e_path).exe")
        chmod("$(e_path).exe", 0o777)
        @test locate(e, prefix; platform=Windows(:x86_64)) == "$(e_path).exe"

        # Test that simply creating a library file doesn't satisfy it if we are
        # testing something that matches the current platform's dynamic library
        # naming scheme, because it must be `dlopen()`able.
        mkpath(last(libdirs(prefix)))
        touch(l_path)
        @test @test_logs (:info, r"^FileProduct .* found at") satisfied(lf, prefix; verbose=true)
        @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") (:info, r"cannot be dlopen'ed") (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true)
        @test @test_logs (:info, r"^FileProduct .* found at") satisfied(lf, prefix; verbose=true, isolate=true)
        @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") (:info, r"cannot be dlopen'ed") (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true, isolate=true)

        # But if it is from a different platform, simple existence will be
        # enough to satisfy a LibraryProduct
        @static if Sys.iswindows()
            p = Linux(:x86_64)
            mkpath(last(libdirs(prefix, p)))
            l_path = joinpath(last(libdirs(prefix, p)), "libfoo.so")
            touch(l_path)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(l, prefix; verbose=true, platform=p)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(l, prefix; verbose=true, platform=p, isolate=true)

            # Check LibraryProduct objects with explicit directory paths
            ld = LibraryProduct("libfoo", :libfoo)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(ld, prefix; verbose=true, platform=p)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(ld, prefix; verbose=true, platform=p, isolate=true)
        else
            p = Windows(:x86_64)
            mkpath(last(libdirs(prefix, p)))
            l_path = joinpath(last(libdirs(prefix, p)), "libfoo.dll")
            touch(l_path)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(l, prefix; verbose=true, platform=p)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(l, prefix; verbose=true, platform=p, isolate=true)

            # Check LibraryProduct objects with explicit directory paths
            ld = LibraryProduct("libfoo", :libfoo)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(ld, prefix; verbose=true, platform=p)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(ld, prefix; verbose=true, platform=p, isolate=true)
        end
    end

    # Ensure that the test suite thinks that these libraries are foreign
    # so that it doesn't try to `dlopen()` them:
    foreign_platform = if platform == Linux(:aarch64)
        # Arbitrary architecture that is not dlopen()'able
        Linux(:powerpc64le)
    else
        # If we're not Linux(:aarch64), then say the libraries are
        Linux(:aarch64)
    end

    # Test for valid library name permutations
    for ext in ["so", "so.1", "so.1.2", "so.1.2.3"]
        temp_prefix() do prefix
            l_path = joinpath(last(libdirs(prefix, foreign_platform)), "libfoo.$ext")
            l = LibraryProduct("libfoo", :libfoo)
            mkdir(dirname(l_path))
            touch(l_path)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(l, prefix; verbose=true, platform=foreign_platform)
        end
    end

    # Test for invalid library name permutations
    for ext in ["1.so", "so.1.2.3a", "so.1.a"]
        temp_prefix() do prefix
            l_path = joinpath(last(libdirs(prefix, foreign_platform)), "libfoo.$ext")
            l = LibraryProduct("libfoo", :libfoo)
            mkdir(dirname(l_path))
            touch(l_path)
            if ext == "1.so"
                @test @test_logs (:info, r"^Found a valid") (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true, platform=foreign_platform)
            else
                @test @test_logs (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true, platform=foreign_platform)
            end
        end
    end

    # Test for proper repr behavior
    temp_prefix() do prefix
        l = LibraryProduct("libfoo", :libfoo)
        @test repr(l) == "LibraryProduct($(repr(["libfoo"])), :libfoo)"
        l = LibraryProduct(["libfoo", "libfoo2"], :libfoo)
        @test repr(l) == "LibraryProduct($(repr(["libfoo", "libfoo2"])), :libfoo)"

        e = ExecutableProduct("fooifier", :fooifier)
        @test repr(e) == "ExecutableProduct([\"fooifier\"], :fooifier)"
        e = ExecutableProduct("fooifier", :fooifier, "bin/qux")
        @test repr(e) == "ExecutableProduct([\"fooifier\"], :fooifier, \"bin/qux\")"

        f = FileProduct(joinpath("etc", "fooifier"), :foo_conf)
        @test repr(f) == "FileProduct([$(repr(joinpath("etc", "fooifier")))], :foo_conf)"

        f = FileProduct(joinpath(prefix, "etc", "foo.conf"), :foo_conf)
        @test repr(f) == "FileProduct([$(repr(joinpath(prefix, "etc", "foo.conf")))], :foo_conf)"
    end

    # Test that FileProduct's can have `${target}` within their paths:
    temp_prefix() do prefix
        multilib_dir = joinpath(prefix, "foo", triplet(platform))
        mkpath(multilib_dir)
        touch(joinpath(multilib_dir, "bar"))

        for path in ("foo/\$target/bar", "foo/\${target}/bar")
            f = FileProduct(path, :bar)
            @test  @test_logs (:info, r"^FileProduct .* found at") satisfied(f, prefix; verbose=true, platform=platform)
        end
    end
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

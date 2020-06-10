using Test
using Pkg.PlatformEngines, Pkg.BinaryPlatforms
using SHA
using BinaryBuilderBase

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

@testset "Packaging" begin
    # Clear out previous build products
    for f in readdir(".")
        if !endswith(f, ".tar.gz") && !endswith(f, ".sha256")
            continue
        end
        Base.rm(f; force=true)
    end

    # Gotta set this guy up beforehand
    tarball_path = nothing
    tarball_hash = nothing

    temp_prefix() do prefix
        # Create random files
        mkpath(bindir(prefix))
        mkpath(last(libdirs(prefix)))
        mkpath(joinpath(prefix, "etc"))
        bar_path = joinpath(bindir(prefix), "bar.sh")
        open(bar_path, "w") do f
            write(f, "#!/bin/sh\n")
            write(f, "echo yolo\n")
        end
        baz_path = joinpath(last(libdirs(prefix)), "baz.so")
        open(baz_path, "w") do f
            write(f, "this is not an actual .so\n")
        end

        qux_path = joinpath(prefix, "etc", "qux.conf")
        open(qux_path, "w") do f
            write(f, "use_julia=true\n")
        end

        # Next, package it up as a .tar.gz file
        tarball_path, tarball_hash = package(prefix, "./libfoo", v"1.0.0"; verbose=true)
        @test isfile(tarball_path)

        # Check that we are calculating the hash properly
        tarball_hash_check = open(tarball_path, "r") do f
            bytes2hex(sha256(f))
        end
        @test tarball_hash_check == tarball_hash

        # Test that packaging into a file that already exists fails
        @test_throws ErrorException package(prefix, "./libfoo", v"1.0.0")
    end

    # Test that we can inspect the contents of the tarball
    contents = list_tarball_files(tarball_path)
    libdir_name = Sys.iswindows() ? "bin" : "lib"
    @test joinpath("bin", "bar.sh") in contents
    @test joinpath(libdir_name, "baz.so") in contents
    @test joinpath("etc", "qux.conf") in contents

    # Cleanup after ourselves
    Base.rm(tarball_path; force=true)
    Base.rm("$(tarball_path).sha256"; force=true)
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

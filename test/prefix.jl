using Test
using Base.BinaryPlatforms
using SHA
using BinaryBuilderBase
using CodecZlib

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

        # Test that we can control libdirs() via platform arguments
        @test libdirs(prefix, Platform("x86_64", "linux")) == [joinpath(prefix, "lib64"), joinpath(prefix, "lib")]
        @test libdirs(prefix, Platform("i686", "linux")) == [joinpath(prefix, "lib")]
        @test libdirs(prefix, Platform("i686", "windows")) == [joinpath(prefix, "bin")]
        @test bindir(prefix) == joinpath(prefix, "bin")
        @test includedir(prefix) == joinpath(prefix, "include")
        @test logdir(prefix) == joinpath(prefix, "logs")
        @test logdir(prefix; subdir="test") == joinpath(prefix, "logs", "test")
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

        for compression_format in ("gzip", "xz", "bzip2")
            # Next, package it up as a tarball
            tarball_path, tarball_hash = @test_logs (:info, r"^Tree hash of contents of") (:info, r"^SHA256 of") begin
                package(prefix, "./libfoo", v"1.0.0"; verbose=true, compression_format)
            end
            @test isfile(tarball_path)

            # Check that we are calculating the hash properly
            tarball_hash_check = open(tarball_path, "r") do f
                bytes2hex(sha256(f))
            end
            @test tarball_hash_check == tarball_hash

            compressor = open(tarball_path) do io
                BinaryBuilderBase.detect_compressor(read(io, 6))
            end
            # Make sure the compression format is what we expect
            @test compressor == compression_format
        end

        # Test that packaging into a file that already exists fails
        @test_throws ErrorException package(prefix, "./libfoo", v"1.0.0")

        # Test error path with unsupported compression format
        @test_throws ErrorException package(prefix, "./libfoo-new", v"1.0.0"; compression_format="unknown")
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

    @testset "Warnings about clashing files" begin
        mktempdir() do tmpdir
            # Create fake source directory
            srcdir = joinpath(tmpdir, "src")
            mkdir(srcdir)
            # Write two files inside the source directory
            srcfile1 = joinpath(srcdir, "file1")
            text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit.\n"
            write(srcfile1, text)
            srcfile2 = joinpath(srcdir, "file2")
            write(srcfile2, text ^ 2)

            # Create the destination directory
            destdir = joinpath(tmpdir, "dest")
            mkdir(destdir)
            destfile1 = joinpath(destdir, "file1")
            # Same text as file1 in the source directory
            write(destfile1, text)
            destfile2 = joinpath(destdir, "file2")
            # Different text from file2 in the source directory
            write(destfile2, text)

            # Set up a symlink tree inside of destdir: make sure only the warning about file2 is issued
            @test_logs (:warn, "Symlink file2 from artifact src already exists in artifact file2") BinaryBuilderBase.symlink_tree(srcdir, destdir)
            BinaryBuilderBase.unsymlink_tree(srcdir, destdir)
        end
    end
end

@testset "Compression" begin
    lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
    mktempdir() do dir
        file = joinpath(dir, "file.txt")
        file_gz = file * ".gz"
        write(file, lorem)
        @test_logs (:info, r"Compressing files in") compress_dir(dir; verbose=true)
        # Check that there is only the compressed file
        @test readdir(dir) == [basename(file_gz)]
        # Decompress it
        @test String(transcode(GzipDecompressor, read(file_gz))) == lorem
    end
end

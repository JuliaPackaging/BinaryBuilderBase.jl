using Test
using BinaryBuilderBase
using BinaryBuilderBase: coerce_source, sourcify, SetupSource, setup
using JSON

@testset "Sources" begin
    @test ArchiveSource("https://ftp.gnu.org/gnu/wget/wget-1.20.3.tar.gz", "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e").unpack_target == ""
    @test ArchiveSource("https://ftp.gnu.org/gnu/wget/wget-1.20.3.tar.gz", "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"; unpack_target = "wget").unpack_target == "wget"
    @test GitSource("https://github.com/jedisct1/libsodium.git", "5b2ea7d73d3ffef2fb93b82b9f112f009d54c6e6").unpack_target == ""
    @test GitSource("https://github.com/jedisct1/libsodium.git", "5b2ea7d73d3ffef2fb93b82b9f112f009d54c6e6"; unpack_target = "libs").unpack_target == "libs"
    @test FileSource("https://curl.haxx.se/ca/cacert-2020-01-01.pem", "adf770dfd574a0d6026bfaa270cb6879b063957177a991d453ff1d302c02081f").filename == "cacert-2020-01-01.pem"
    @test FileSource("https://curl.haxx.se/ca/cacert-2020-01-01.pem", "adf770dfd574a0d6026bfaa270cb6879b063957177a991d453ff1d302c02081f"; filename="cacert.pem").filename == "cacert.pem"

    @test SetupSource("https://ftp.gnu.org/gnu/wget/wget-1.20.3.tar.gz", "wget-1.20.3.tar.gz", "", "") isa SetupSource{ArchiveSource}
    @test SetupSource("https://ftp.gnu.org/gnu/wget/wget-1.20.3.zip", "wget-1.20.3.zip", "", "")    isa SetupSource{ArchiveSource}
    @test SetupSource("https://github.com/jedisct1/libsodium.git", "libsodium.git", "", "")       isa SetupSource{GitSource}
    @test SetupSource("git://developer.intra2net.com/libftdi", "libftdi", "", "") isa SetupSource{GitSource}
    @test SetupSource("https://curl.haxx.se/ca/cacert-2020-01-01.pem", "cacert-2020-01-01.pem", "", "")   isa SetupSource{FileSource}

    @testset "Download and setup" begin
        mktempdir() do dir
            cd(dir) do
                as = ArchiveSource("https://github.com/ralna/ARCHDefs/archive/v2.0.3x.tar.gz", "6583e27f84338447767bbdf4335514c8836ae4ad54f5e66280307e8b57189cff")
                # Download the source
                sas = @test_logs (:info, r"Downloading .* to.*") download_source(as; verbose = true, downloads_dir = dir)
                # Check that the cache is found
                @test @test_logs (:info, r"Cached file found in .*") download_source(as; verbose = true, downloads_dir = dir) == sas
                fs = FileSource("https://github.com/ralna/ARCHDefs/archive/v2.0.3x.tar.gz", "6583e27f84338447767bbdf4335514c8836ae4ad54f5e66280307e8b57189cff"; filename = "file-source.tar.gz")
                # Re-fetch the same tarball, as a `FileSource` this time
                sfs = @test_logs (:info, r"Cached file found in .*") download_source(fs; verbose = true, downloads_dir = dir)
                gs = GitSource("https://github.com/ralna/ARCHDefs.git", "fc8c5960c3a6d26970ab245241cfc067fe4ecfdd")
                # Clone the repo once
                sgs = @test_logs (:info, r"^Cloning") download_source(gs; verbose = true, downloads_dir = dir)
                # Fetch again the repo to make sure cache works
                @test @test_logs (:info, r"^Using cached git repository") download_source(gs; verbose = true, downloads_dir = dir) == sgs
                # Fetch the temp directory as a `DirectorySource`
                ds_follow = DirectorySource("./bundled_follow"; follow_symlinks=true)
                patchdir = abspath(joinpath(dir, ds_follow.path, "patches_follow"))
                mkpath(patchdir)
                write(abspath(joinpath(patchdir, "fix-windows-headers.patch")), "This is a patch file")
                # Create a symlink.  We'll want to check that `setup` follows symlinks
                link = joinpath(patchdir, "link.patch")
                symlink("fix-windows-headers.patch", link)
                @test islink(link)
                sds_follow = @test_logs (:info, r"^Directory .* found") download_source(ds_follow; verbose = true)
                # Try to fetch a non-existing directory
                @test_throws ErrorException download_source(DirectorySource(joinpath(dir, "does_not_exist")); verbose = true)
                # Another directory source, which doesn't follow symlinks
                ds_nofollow = DirectorySource("./bundled_nofollow")
                patchdir = abspath(joinpath(dir, ds_nofollow.path, "patches_nofollow"))
                mkpath(patchdir)
                write(abspath(joinpath(patchdir, "fix-windows-headers.patch")), "This is a patch file")
                # Create a symlink.  We'll want to check that `setup` follows symlinks
                link = joinpath(patchdir, "link.patch")
                symlink("fix-windows-headers.patch", link)
                @test islink(link)
                sds_nofollow = @test_logs (:info, r"^Directory .* found") download_source(ds_nofollow; verbose = true)
                # Yet another directory source, this time one that tries to unpack into a subdirectory
                ds_target = DirectorySource("./bundled_subdir_target", target="ds_unpack_target")
                filedir = mkpath(abspath(joinpath(dir, ds_target.path)))
                write(abspath(joinpath(filedir, "fix-windows-headers.patch")), "This is a patch file")
                sds_target = @test_logs (:info, r"^Directory .* found") download_source(ds_target; verbose = true)
                # Try to fetch a non-existing directory
                @test_throws ErrorException download_source(DirectorySource(joinpath(dir, "does_not_exist")); verbose = true)

                # Setup the sources with `setup`
                srcdir = joinpath(dir, "srcdir")
                target = joinpath(srcdir, as.unpack_target)
                @test_logs (:info, r"^Extracting tarball") setup(sas, target, true; tar_flags = "xof")
                @test isdir(target)
                target = joinpath(srcdir, fs.filename)
                @test_logs (:info, r"^Copying") setup(sfs, target, true)
                @test isfile(target)
                target = joinpath(srcdir, gs.unpack_target)
                @test_logs (:info, r"^Checking ARCHDefs.git-[0-9a-fA-F]{64} out to ARCHDefs...") setup(sgs, target, true)
                @test isdir(target)
                # Setup directory source with links to follow
                target = abspath(joinpath(srcdir, "patches_follow"))
                @test_logs (:info, "Copying content of bundled_follow in srcdir...") setup(sds_follow, srcdir, true)
                @test isdir(target)
                # Make sure that the symlinks are followed
                @test isfile(joinpath(target, "link.patch"))
                @test !islink(joinpath(target, "link.patch"))
                # Setup directory source with links to not follow
                target = abspath(joinpath(srcdir, "patches_nofollow"))
                @test_logs (:info, "Copying content of bundled_nofollow in srcdir...") setup(sds_nofollow, srcdir, true)
                @test isdir(target)
                # Make sure that the symlinks are not followed
                @test isfile(joinpath(target, "link.patch"))
                @test islink(joinpath(target, "link.patch"))

                # Make sure in srcdir there are all files and directories we expect
                @test Set(readdir(srcdir)) == Set(["ARCHDefs", "ARCHDefs-2.0.3x", fs.filename, "patches_follow", "patches_nofollow"])

                # Setup the sources with `setup_workspace`
                workspace = joinpath(dir, "workspace")
                mkpath(workspace)
                prefix = @test_logs(
                    (:info, r"^Copying"), (:info, r"^Copying"), (:info, r"^Copying"), (:info, r"^Copying"), (:info, r"^Checking"),
                    setup_workspace(workspace, [sfs, sds_follow, sds_nofollow, sds_target, sgs], HostPlatform(); verbose=true)
                )
                @test Set(readdir(joinpath(prefix.path, "srcdir"))) == Set(
                    ["ARCHDefs", "file-source.tar.gz", "patches_follow", "patches_nofollow", "ds_unpack_target"]
                )
                @test isfile(joinpath(prefix.path, "srcdir", "ds_unpack_target", "fix-windows-headers.patch"))
            end
        end
    end

    as = ArchiveSource("https://ftp.gnu.org/gnu/wget/wget-1.20.3.tar.gz", "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e")
    fs = FileSource("https://ftp.gnu.org/gnu/wget/wget-1.20.3.tar.gz.sig", "7b295c84ab6f90c328a203e234e4b2f5f45cb8d2e29eac43a977073933cd49a2")
    gs = GitSource("https://github.com/jedisct1/libsodium.git", "5b2ea7d73d3ffef2fb93b82b9f112f009d54c6e6")
    ds = DirectorySource("./bundled")

    @testset "JSON (de)serialization" begin
        jas = JSON.lower(as)
        @test jas == Dict("type" => "archive", "url" => as.url, "hash" => as.hash, "unpack_target" => as.unpack_target)
        @test sourcify(jas) == as
        jfs = JSON.lower(fs)
        @test jfs == Dict("type" => "file", "url" => fs.url, "hash" => fs.hash, "filename" => fs.filename)
        @test sourcify(jfs) == fs
        jgs = JSON.lower(gs)
        @test jgs == Dict("type" => "git", "url" => gs.url, "hash" => gs.hash, "unpack_target" => gs.unpack_target)
        @test sourcify(jgs) == gs
        jds = JSON.lower(ds)
        @test jds == Dict("type" => "directory", "path" => ds.path, "target" => "", "follow_symlinks" => false)
        @test sourcify(jds) == ds

        @test_throws ErrorException sourcify(Dict("type" => "error"))
    end

    @testset "Compat" begin
        @test coerce_source(as) == as
        @test @test_logs (:warn, "Using a pair as source is deprecated, use ArchiveSource instead") coerce_source(as.url => as.hash) == as
        @test coerce_source(fs) == fs
        @test @test_logs (:warn, "Using a pair as source is deprecated, use FileSource instead") coerce_source(fs.url => fs.hash) == fs
        @test coerce_source(gs) == gs
        @test @test_logs (:warn, "Using a pair as source is deprecated, use GitSource instead") coerce_source(gs.url => gs.hash) == gs
        @test coerce_source(ds) == ds
        @test @test_logs (:warn, "Using a string as source is deprecated, use DirectorySource instead") coerce_source(ds.path) == ds
    end
end

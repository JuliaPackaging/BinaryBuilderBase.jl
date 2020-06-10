using Test
using BinaryBuilderBase

@testset "Sources" begin
    @test ArchiveSource("https://ftp.gnu.org/gnu/wget/wget-1.20.3.tar.gz", "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e").unpack_target == ""
    @test ArchiveSource("https://ftp.gnu.org/gnu/wget/wget-1.20.3.tar.gz", "31cccfc6630528db1c8e3a06f6decf2a370060b982841cfab2b8677400a5092e"; unpack_target = "wget").unpack_target == "wget"
    @test GitSource("https://github.com/jedisct1/libsodium.git", "5b2ea7d73d3ffef2fb93b82b9f112f009d54c6e6").unpack_target == ""
    @test GitSource("https://github.com/jedisct1/libsodium.git", "5b2ea7d73d3ffef2fb93b82b9f112f009d54c6e6"; unpack_target = "libs").unpack_target == "libs"
    @test FileSource("https://curl.haxx.se/ca/cacert-2020-01-01.pem", "adf770dfd574a0d6026bfaa270cb6879b063957177a991d453ff1d302c02081f").filename == "cacert-2020-01-01.pem"
    @test FileSource("https://curl.haxx.se/ca/cacert-2020-01-01.pem", "adf770dfd574a0d6026bfaa270cb6879b063957177a991d453ff1d302c02081f"; filename="cacert.pem").filename == "cacert.pem"

    @testset "Sources -- Download" begin
        mktempdir() do dir
            as = ArchiveSource("https://github.com/ralna/ARCHDefs/archive/v2.0.3x.tar.gz", "6583e27f84338447767bbdf4335514c8836ae4ad54f5e66280307e8b57189cff")
            # Download the source
            @test_logs (:info, r"^No hash cache found") (:info, r"Calculated hash") download_source(as; verbose = true, downloads_dir = dir)
            # Check that the cache is found
            @test_logs (:info, r"^Destination file .* already exists") (:info, r"Hash cache is consistent, returning true") download_source(as; verbose = true, downloads_dir = dir)
            fs = FileSource("https://github.com/ralna/ARCHDefs/archive/v2.0.3x.tar.gz", "6583e27f84338447767bbdf4335514c8836ae4ad54f5e66280307e8b57189cff")
            # Re-fetch the same tarball, as a `FileSource` this time
            @test_logs (:info, r"^Destination file .* already exists") (:info, r"Hash cache is consistent, returning true") download_source(fs; verbose = true, downloads_dir = dir)
            gs = GitSource("https://github.com/ralna/ARCHDefs", "fc8c5960c3a6d26970ab245241cfc067fe4ecfdd")
            # Clone the repo once
            @test_logs (:info, r"^Cloning") download_source(gs; verbose = true, downloads_dir = dir)
            # Fetch again the repo to make sure cache works
            @test_logs (:info, r"^Cached repository found in") download_source(gs; verbose = true, downloads_dir = dir)
            # Fetch the temp directory as a `DirectorySource`
            @test_logs (:info, r"^Directory .* found") download_source(DirectorySource(dir); verbose = true)
            # Try to fetch a non-existing directory
            @test_throws ErrorException download_source(DirectorySource(joinpath(dir, "does_not_exist")); verbose = true)
        end
    end
end

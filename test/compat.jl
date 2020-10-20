using Test
using BinaryBuilderBase: extract_kwargs, extract_fields, strip_backslash, ArchiveSource

@testset "Compat functions" begin
    foo(; kwargs...) = collect(extract_kwargs(kwargs, (:bar, :qux)))
    @test foo(; a = 1) == Pair[]
    @test foo(; bar = 2, b = 3) == [:bar => 2]
    @test foo(; c = 4, qux = 5) == [:qux => 5]
    @test Set(foo(; qux = 6, d = 7, bar = 8)) == Set([:bar => 8, :qux => 6])

    @test extract_fields(ArchiveSource("http://example.org", "this is the hash"; unpack_target = "target")) == Dict("url" => "http://example.org", "hash" => "this is the hash", "unpack_target" => "target")

    @test strip_backslash("/home/wizard") == "/home/wizard"
    @test strip_backslash("/home/wizard/") == "/home/wizard"
    @test strip_backslash("/home//wizard///") == "/home//wizard"
    @test strip_backslash("wizard.jl") == "wizard.jl"
    # Test integration with `basename`
    @test basename(strip_backslash("/home/wizard")) == "wizard"
    @test basename(strip_backslash("/home/wizard/")) == "wizard"
    @test basename(strip_backslash("/home//wizard///")) == "wizard"
    @test basename(strip_backslash("wizard.jl")) == "wizard.jl"
end

using BinaryBuilderBase: download_verify, list_tarball_files
@testset "ArchiveUtils" begin
    mktempdir() do dir
        # Test that we can download, then list, the contents of .tar.gz, .tar.bz2 and .tar.xz files.
        for (url, hash) in [("https://github.com/staticfloat/small_bin/raw/master/socrates.tar.gz",
                             "e65d2f13f2085f2c279830e863292312a72930fee5ba3c792b14c33ce5c5cc58"),
                            ("https://github.com/staticfloat/small_bin/raw/master/socrates.tar.xz",
                             "61bcf109fcb749ee7b6a570a6057602c08c836b6f81091eab7aa5f5870ec6475"),
                            ("https://github.com/staticfloat/small_bin/raw/master/socrates.tar.bz2",
                             "13fc17b97be41763b02cbb80e9d048302cec3bd3d446c2ed6e8210bddcd3ac76")]
            # First, download to a path:
            path = joinpath(dir, basename(url))
            @test_logs (:info, "Downloading $(url) to $(path)...") download_verify(url, hash, path)
            @test isfile(path)

            # Ensure that we can list the tarball:
            @test "bin/socrates" in list_tarball_files(path)
        end

        # Test that a 404 throws
        url = "https://github.com/not_a_file"
        dest = joinpath(dir, "blah")
        @test_logs (:info, "Downloading $(url) to $(dest)...") @test_throws ErrorException download_verify(url, "0"^64, dest)

        # Test that a bad hash logs a message and fails
        url = "https://github.com/staticfloat/small_bin/raw/master/socrates.tar.xz"
        dest = joinpath(dir, "blah2")
        @test_logs (:error, r"Hash Mismatch") (:info, "Downloading $(url) to $(dest)...") match_mode=:any @test_throws ErrorException begin
            download_verify(url, "0"^64, dest)
        end
    end
end

using Test
using BinaryBuilderBase
using BinaryBuilderBase: supported_marchs, dlext, exeext

@testset "Wrappers utilities" begin
    @test nbits(Linux(:i686)) == 32
    @test nbits(ExtendedPlatform(Linux(:x86_64); march="avx")) == 64
    @test nbits(Linux(:armv7l)) == 32
    @test nbits(ExtendedPlatform(Linux(:aarch64); cuda="10.1")) == 64
    @test nbits(Linux(:powerpc64le)) == 64
    @test nbits(AnyPlatform()) == 64
    @test_throws ErrorException nbits(UnknownPlatform())

    @test proc_family(Linux(:i686)) == :intel
    @test proc_family(ExtendedPlatform(Linux(:x86_64); march="avx")) == :intel
    @test proc_family(Linux(:armv7l)) == :arm
    @test proc_family(ExtendedPlatform(Linux(:aarch64); cuda="10.1")) == :arm
    @test proc_family(Linux(:powerpc64le)) == :power
    @test proc_family(AnyPlatform()) == :intel
    @test_throws ErrorException proc_family(UnknownPlatform())

    @test supported_marchs(Linux(:i686)) == []
    @test supported_marchs(Linux(:x86_64)) == ["avx", "avx2", "avx512", "x86_64"]
    @test supported_marchs(Linux(:armv7l)) == ["armv7l", "neon", "vfp4"]
    # This extended platform doesn't specify a microarchitecture, so we can support all of them
    @test supported_marchs(ExtendedPlatform(Linux(:aarch64); cuda="10.1")) == ["armv8", "carmel", "thunderx2"]
    @test supported_marchs(Linux(:powerpc64le)) == []
    # This extended platform specifies a valid microarchitecture, so we support only the given architecture
    @test supported_marchs(ExtendedPlatform(Linux(:x86_64); march="avx")) == ["avx"]
    # This extended platform specifies an invalid microarchitecture (it is valid
    # for a different platform), so we don't support it
    @test supported_marchs(ExtendedPlatform(Linux(:x86_64); march="carmel")) == []
    @test supported_marchs(AnyPlatform()) == []
    @test supported_marchs(UnknownPlatform()) == []

    @test dlext(Linux(:i686)) == "so"
    @test dlext(FreeBSD(:x86_64)) == "so"
    @test dlext(MacOS(:x86_64)) == "dylib"
    @test dlext(Windows(:i686)) == "dll"
    @test dlext(ExtendedPlatform(Linux(:x86_64); march="avx512")) == "so"
    @test_throws ErrorException dlext(AnyPlatform())
    @test_throws ErrorException dlext(UnknownPlatform())

    @test exeext(Linux(:i686)) == ""
    @test exeext(FreeBSD(:x86_64)) == ""
    @test exeext(MacOS(:x86_64)) == ""
    @test exeext(Windows(:i686)) == ".exe"
    @test exeext(ExtendedPlatform(Linux(:x86_64); march="avx512")) == ""
    @test_throws ErrorException exeext(AnyPlatform())
    @test_throws ErrorException exeext(UnknownPlatform())

    @test aatriplet(ExtendedPlatform(Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(libgfortran_version=v"4.0.0")); march="avx", cuda="9.2")) == "x86_64-linux-gnu"
end

# Are we using docker? If so, test that the docker runner works...
@testset "Runner utilities" begin
    # Test that is_ecryptfs works for something we're certain isn't encrypted
    if isdir("/proc")
        isecfs = (false, "/proc/")
        @test_logs (:info, "Checking to see if /proc/ is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc"; verbose=true) == isecfs
        @test_logs (:info, "Checking to see if /proc/ is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc/"; verbose=true) == isecfs
        @test_logs (:info, "Checking to see if /proc/not_a_file is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc/not_a_file"; verbose=true) == isecfs
    else
        @test_logs (:info, "Checking to see if /proc/ is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc"; verbose=true) == (false, "/proc")
        @test_logs (:info, "Checking to see if /proc/ is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc/"; verbose=true) == (false, "/proc/")
        @test_logs (:info, "Checking to see if /proc/not_a_file is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc/not_a_file"; verbose=true) == (false, "/proc/not_a_file")
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

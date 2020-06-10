using Test
using BinaryBuilderBase

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

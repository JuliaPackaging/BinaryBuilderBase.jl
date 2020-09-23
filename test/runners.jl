using Test
using BinaryBuilderBase
using BinaryBuilderBase: dlext, exeext

@testset "Wrappers utilities" begin
    @test nbits(Platform("i686", "linux")) == 32
    @test nbits(Platform("x86_64", "linux"; march="avx")) == 64
    @test nbits(Platform("armv7l", "linux")) == 32
    @test nbits(Platform("aarch64", "linux"; cuda="10.1")) == 64
    @test nbits(Platform("powerpc64le", "linux")) == 64
    @test nbits(AnyPlatform()) == 64

    @test proc_family(Platform("i686", "linux")) == :intel
    @test proc_family(Platform("x86_64", "linux"; march="avx")) == :intel
    @test proc_family(Platform("armv7l", "linux")) == :arm
    @test proc_family(Platform("aarch64", "linux"; cuda="10.1")) == :arm
    @test proc_family(Platform("powerpc64le", "linux")) == :power
    @test proc_family(AnyPlatform()) == :intel

    @test platform_exeext(Platform("i686", "linux")) == ""
    @test platform_exeext(Platform("x86_64", "freebsd")) == ""
    @test platform_exeext(Platform("x86_64", "macos")) == ""
    @test platform_exeext(Platform("i686", "windows")) == ".exe"
    @test platform_exeext(Platform("x86_64", "linux"; march="avx512")) == ""

    @test aatriplet(Platform("x86_64", "linux"; libc="glibc", libgfortran_version=v"4.0.0", march="avx", cuda="9.2")) == "x86_64-linux-gnu"
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

    @testset "Compilation" begin
        mktempdir() do dir
            ur = preferred_runner()(dir; platform=Linux(:x86_64; libc=:musl))
            iobuff = IOBuffer()
            @test run(ur, `/bin/bash -c "echo 'int main() {return 0;}' | cc -x c -"`, iobuff; tee_stream=devnull)
            seekstart(iobuff)
            @test split(String(read(iobuff)), "\n")[2] == ""
        end
    end

    @testset "Locking microarchitecture" begin
        mktempdir() do dir
            platform = Linux(:x86_64; libc=:musl)
            cmd = `/bin/bash -c "echo 'int main() {return 0;}' | cc -x c -march=native -"`
            ur = preferred_runner()(dir; platform=platform, lock_microarchitecture=true)
            iobuff = IOBuffer()
            @test !run(ur, cmd, iobuff; tee_stream=devnull)
            seekstart(iobuff)
            @test split(String(read(iobuff)), "\n")[2] == "Cannot force an architecture"

            ur = preferred_runner()(dir; platform=platform, lock_microarchitecture=false)
            iobuff = IOBuffer()
            @test run(ur, cmd, iobuff; tee_stream=devnull)
            seekstart(iobuff)
            @test split(String(read(iobuff)), "\n")[2] == ""
        end
    end

    @testset "Unsafe flags" begin
        mktempdir() do dir
            platform = Linux(:x86_64; libc=:musl)
            cmd = `/bin/bash -c "echo 'int main() {return 0;}' | cc -x c -Ofast -"`
            ur = preferred_runner()(dir; platform=platform, allow_unsafe_flags=false)
            iobuff = IOBuffer()
            @test !run(ur, cmd, iobuff; tee_stream=devnull)
            seekstart(iobuff)
            lines = split(String(read(iobuff)), "\n")
            @test lines[2] == "You used one or more of the unsafe flags: -Ofast, -ffast-math, -funsafe-math-optimizations"
            @test lines[3] == "Please repent."

            ur = preferred_runner()(dir; platform=platform, allow_unsafe_flags=true)
            iobuff = IOBuffer()
            @test run(ur, cmd, iobuff; tee_stream=devnull)
            seekstart(iobuff)
            @test split(String(read(iobuff)), "\n")[2] == ""
        end
    end
end

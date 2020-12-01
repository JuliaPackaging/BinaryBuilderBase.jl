using Test
using BinaryBuilderBase
using BinaryBuilderBase: platform_dlext, platform_exeext

@testset "Wrappers utilities" begin
    @test nbits(Platform("i686", "linux")) == 32
    @test nbits(Platform("x86_64", "linux"; march="avx")) == 64
    @test nbits(Platform("armv7l", "linux")) == 32
    @test nbits(Platform("aarch64", "linux"; cuda="10.1")) == 64
    @test nbits(Platform("powerpc64le", "linux")) == 64
    @test nbits(AnyPlatform()) == 64

    @test proc_family(Platform("i686", "linux")) == "intel"
    @test proc_family(Platform("x86_64", "linux"; march="avx")) == "intel"
    @test proc_family(Platform("armv7l", "linux")) == "arm"
    @test proc_family(Platform("aarch64", "linux"; cuda="10.1")) == "arm"
    @test proc_family(Platform("powerpc64le", "linux")) == "power"
    @test proc_family(AnyPlatform()) == "any"

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
            ur = preferred_runner()(dir; platform=Platform("x86_64", "linux"; libc="musl"))
            iobuff = IOBuffer()
            @test run(ur, `/bin/bash -c "echo test"`, iobuff)
            seek(iobuff, 0)
            # Test that we get the output we expect (e.g. the second line is `test`)
            @test split(String(read(iobuff)), "\n")[2] == "test"
        end
    end

    if lowercase(get(ENV, "BINARYBUILDER_FULL_SHARD_TEST", "false")) == "true"
        @info("Beginning full shard test... (this can take a while)")
        platforms = supported_platforms()
    else
        platforms = (Platform("x86_64", "linux"; libc="musl"),)
    end

    # Checks that the wrappers provide the correct C++ string ABI
    @testset "Compilation - C++ string ABI" begin
        mktempdir() do dir
            # Host is x86_64-linux-musl-cxx11 and target is x86_64-linux-musl-cxx03
            ur = preferred_runner()(dir; platform=Platform("x86_64", "linux"; libc="musl", cxxstring_abi="cxx03"), preferred_gcc_version=v"5")
            iobuff = IOBuffer()
            test_script = raw"""
            set -e

            # Building for the target uses C++03 string ABI
            echo 'int main() {return 0;}' | SUPER_VERBOSE=1 ${CC} -x c - 2>&1 | grep -- "-D_GLIBCXX_USE_CXX11_ABI=0"

            # Building for the host uses C++11 string ABI
            echo 'int main() {return 0;}' | SUPER_VERBOSE=1 ${HOSTCC} -x c - 2>&1 | grep -v -- "-D_GLIBCXX_USE_CXX11_ABI=0"
            """
            @test run(ur, `/bin/bash -c "$(test_script)"`, iobuff; tee_stream=devnull)
        end
    end

    # This tests only that compilers for all platforms can build a simple C program
    @testset "Compilation - $(platform)" for platform in platforms
        mktempdir() do dir
            ur = preferred_runner()(dir; platform=platform)
            iobuff = IOBuffer()
            @test run(ur, `/bin/bash -c "echo 'int main() {return 0;}' | cc -x c -"`, iobuff; tee_stream=devnull)
            seekstart(iobuff)
            @test split(String(read(iobuff)), "\n")[2] == ""
        end
    end

    # This tests that compilers for all Intel Linux platforms can build a simple
    # C program that we can also run
    @testset "Compilation and running" begin
        mktempdir() do dir
            platforms = filter(p -> Sys.islinux(p) && proc_family(p) == "intel", supported_platforms())

            @testset "C - $(platform)" for platform in platforms
                ur = preferred_runner()(dir; platform=platform)
                iobuff = IOBuffer()
                test_c = """
                #include <stdio.h>
                int main() {
                    printf("Hello World!\\n");
                    return 0;
                }
                """
                cmd = `/bin/bash -c "echo '$(test_c)' > test.c && cc -o test test.c && ./test"`
                @test run(ur, cmd, iobuff; tee_stream=devnull)
                seekstart(iobuff)
                # Test that we get the output we expect
                @test endswith(readchomp(iobuff), "Hello World!")
            end

            # This tests that compilers for all Intel Linux platforms can build a simple
            # Fortran program that we can also run
            @testset "Fortran - $(platform)" for platform in filter(p -> Sys.islinux(p) && proc_family(p) == "intel", supported_platforms())
                ur = preferred_runner()(dir; platform=platform)
                iobuff = IOBuffer()
                test_f = """
                      program hello
                          print *, "Hello World!"
                      end program
                """
                cmd = `/bin/bash -c "echo '$(test_f)' > test.f && gfortran -o test test.f && ./test"`
                if arch(platform) == "i686" && libc(platform) == "musl"
                    @test_broken run(ur, cmd, iobuff; tee_stream=devnull)
                else
                    @test run(ur, cmd, iobuff; tee_stream=devnull)
                    seekstart(iobuff)
                    # Test that we get the output we expect
                    @test endswith(readchomp(iobuff), "Hello World!")
                end
            end
        end
    end

    @testset "Locking microarchitecture" begin
        mktempdir() do dir
            platform = Platform("x86_64", "linux"; libc="musl")
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
            platform = Platform("x86_64", "linux"; libc="musl")
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

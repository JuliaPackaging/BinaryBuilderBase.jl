using Test
using BinaryBuilderBase
using BinaryBuilderBase: platform_dlext, platform_exeext, prefer_clang
using Pkg

@testset "Wrappers utilities" begin
    @test nbits(Platform("i686", "linux")) == 32
    @test nbits(Platform("x86_64", "linux"; march="avx")) == 64
    @test nbits(Platform("armv7l", "linux")) == 32
    @test nbits(Platform("aarch64", "linux"; cuda="10.1")) == 64
    @test nbits(Platform("powerpc64le", "linux")) == 64
    @test nbits(Platform("riscv64", "linux")) == 64
    @test nbits(AnyPlatform()) == 64

    @test proc_family(Platform("i686", "linux")) == "intel"
    @test proc_family(Platform("x86_64", "linux"; march="avx")) == "intel"
    @test proc_family(Platform("armv7l", "linux")) == "arm"
    @test proc_family(Platform("aarch64", "linux"; cuda="10.1")) == "arm"
    @test proc_family(Platform("powerpc64le", "linux")) == "power"
    @test proc_family(Platform("riscv64", "linux")) == "riscv"
    @test proc_family(AnyPlatform()) == "any"

    @test platform_exeext(Platform("i686", "linux")) == ""
    @test platform_exeext(Platform("x86_64", "freebsd")) == ""
    @test platform_exeext(Platform("x86_64", "macos")) == ""
    @test platform_exeext(Platform("i686", "windows")) == ".exe"
    @test platform_exeext(Platform("x86_64", "linux"; march="avx512")) == ""

    @test aatriplet(Platform("x86_64", "linux"; libc="glibc", libgfortran_version=v"4.0.0", march="avx", cuda="9.2")) == "x86_64-linux-gnu"

    @test prefer_clang(Platform("x86_64", "freebsd"))
    @test prefer_clang(Platform("aarch64", "macos"))
    @test !prefer_clang(Platform("powerpc64le", "linux"))
    @test !prefer_clang(Platform("riscv64", "linux"))
    @test !prefer_clang(Platform("x86_64", "linux"))
    @test prefer_clang(Platform("x86_64", "linux"; sanitize="memory"))
    @test !prefer_clang(Platform("x86_64", "linux"; sanitize="thread"))
end

@testset "with_logfile" begin
    mktempdir() do dir
        logfile = joinpath(dir, "dir", "logfile.txt")
        with_logfile(logfile) do io
            print(io, logfile)
        end
        @test readchomp(logfile) == logfile
        # Test writing on an existing file
        with_logfile(logfile) do io
            print(io, logfile * logfile)
        end
        @test readchomp(logfile) == logfile * logfile

        # Test using a Prefix as argument
        prefix = Prefix(dir)
        subdir = "my_package"
        ldir = logdir(prefix; subdir)
        name = "logfile.txt"
        logfile = joinpath(ldir, name)
        with_logfile(prefix, name; subdir) do io
            print(io, logfile)
        end
        @test readchomp(logfile) == logfile
    end
end

# Are we using docker? If so, test that the docker runner works...
@testset "Runner utilities" begin
    # Test that is_ecryptfs works for something we're certain isn't encrypted

    if isdir("/proc") && Sys.islinux()
        isecfs = (false, "/proc/")
        @test_logs (:info, "Checking to see if /proc/ is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc"; verbose=true) == isecfs
        @test_logs (:info, "Checking to see if /proc/ is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc/"; verbose=true) == isecfs
        @test_logs (:info, "Checking to see if /proc/not_a_file is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc/not_a_file"; verbose=true) == isecfs
    elseif Sys.islinux()
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
            # Make sure we can start a shell in a runner when the bootstrap list is non-empty
            @eval BinaryBuilderBase push!(bootstrap_list, :rootfs, :platform_support)
            ur = preferred_runner()(dir; platform=Platform("x86_64", "linux"; libc="musl"))
            iobuff = IOBuffer()
            @test run(ur, `/bin/bash -c "echo test"`, iobuff)
            seek(iobuff, 0)
            # Test that we get the output we expect (e.g. the second line is `test`)
            @test readlines(iobuff)[2] == "test"
            # Restore empty bootstrap list
            @eval BinaryBuilderBase empty!(bootstrap_list)
        end
    end

    @testset "run_interactive" begin
        platform = default_host_platform
        io = IOBuffer()
        @test run_interactive(preferred_runner()(mktempdir(); platform), `/bin/bash -c "echo hello world"`, stdout=io)
        s = String(take!(io))
        @test s == "hello world\n"
        # Make sure that `run_interactive` consistently throws an error when the process fails,
        # whatever is the type of `stdout`, or it consistently ignores failures if so requested.
        # Ref: https://github.com/JuliaPackaging/BinaryBuilderBase.jl/pull/201#issuecomment-1003192121
        cmd = `/bin/bash -c "false"`
        @test_throws ProcessFailedException run_interactive(preferred_runner()(mktempdir(); platform), cmd)
        @test_throws ProcessFailedException run_interactive(preferred_runner()(mktempdir(); platform), cmd; stdout=IOBuffer())
        cmd = Cmd(`/bin/bash -c "false"`; ignorestatus=true)
        @test !run_interactive(preferred_runner()(mktempdir(); platform), cmd)
        @test !run_interactive(preferred_runner()(mktempdir(); platform), cmd; stdout=IOBuffer())
    end

    if lowercase(get(ENV, "BINARYBUILDER_FULL_SHARD_TEST", "false")) == "true"
        @info("Beginning full shard test... (this can take a while)")
        platforms = supported_platforms()
        elf_platforms = filter(p -> Sys.islinux(p) || Sys.isfreebsd(p), supported_platforms())
    else
        platforms = (default_host_platform,)
        elf_platforms = (default_host_platform,)
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

    # Checks that the compiler/linker include a build-id
    # This is only available on ELF-based platforms
    @testset "Compilation - build-id note $(platform) - $(compiler)" for platform in elf_platforms, compiler in ("cc", "gcc", "clang", "c++", "g++", "clang++")
        mktempdir() do dir
            ur = preferred_runner()(dir; platform=platform)
            iobuff = IOBuffer()
            test_c = """
                #include <stdlib.h>
                int test(void) {
                    return 0;
                }
                """
            test_script = """
                set -e
                # Make sure setting `CCACHE` doesn't affect the compiler wrappers.
                export CCACHE=pwned
                export USE_CCACHE=false
                echo '$(test_c)' > test.c
                # Build shared library
                $(compiler) -shared test.c -o libtest.\${dlext}

                # Print out the notes in the library
                readelf -n libtest.\${dlext}
                """
            cmd = `/bin/bash -c "$(test_script)"`
            @test run(ur, cmd, iobuff)
            seekstart(iobuff)
            # Make sure the compiled library has the note section for the build-id
            @test occursin("NT_GNU_BUILD_ID", readchomp(iobuff))
        end
    end

    # This tests only that compilers for all platforms can build and link simple C code
    @testset "Compilation - $(platform) - $(compiler)" for platform in platforms, compiler in ("cc", "gcc", "clang")
        mktempdir() do dir
            # if compiler == "clang"
            #     ur = preferred_runner()(dir; platform=platform, preferred_gcc_version=v"5") #TODO: Fix CI disk size issues to allow this
            # else
            #     ur = preferred_runner()(dir; platform=platform)
            # end
            ur = preferred_runner()(dir; platform=platform)
            iobuff = IOBuffer()
            test_c = """
                #include <stdlib.h>
                int test(void) {
                    return 0;
                }
                """
            main_c = """
            int test(void);
            int main(void) {
                return test();
            }
            """
            test_script = """
                set -e
                # Make sure setting `CCACHE` doesn't affect the compiler wrappers.
                export CCACHE=pwned
                export USE_CCACHE=false
                echo '$(test_c)' > test.c
                echo '$(main_c)' > main.c
                # Build object file
                $(compiler) -Werror -c test.c -o test.o
                # Build shared library
                $(compiler) -Werror -shared test.c -o libtest.\${dlext}
                # Build and link program with object file
                $(compiler) -Werror -o main main.c test.o
                # Build and link program with shared library
                $(compiler) -Werror -o main main.c -L. -ltest
                """
            cmd = `/bin/bash -c "$(test_script)"`
            @test run(ur, cmd, iobuff)
            seekstart(iobuff)
            # Make sure `iobuff` contains only the input command, no other text
            @test readchomp(iobuff) == string(cmd)
        end
    end

    # This tests only that compilers for all platforms can build and link simple C++ code
    # Note: we test the slightly weird `clang -x c++` as compiler driver because that's used
    # in some cases and we want to make sure it works correctly.
    @testset "Compilation - $(platform) - $(compiler)" for platform in platforms, (compiler, linker) in (("c++", "c++"), ("g++", "g++"), ("clang -x c++", "clang++"))
        mktempdir() do dir
            ur = preferred_runner()(dir; platform=platform)
            iobuff = IOBuffer()
            needfpic = Sys.iswindows(platform) ? "" : "-fPIC"
            test_cpp = """
                #include <complex>
                std::complex<double> add(std::complex<double> a, std::complex<double> b) {
                    return a + b;
                }
                """
            main_cpp = """
                #include <complex>
                std::complex<double> add(std::complex<double> a, std::complex<double> b);
                int main(void) {
                    std::complex<double> z3 = add(std::complex<double>(1.,2.),std::complex<double>(4.,2.));
                    return 0;
                }
                """
            main_c = """
                int main(void) {
                    return 0;
                }
                """
            test_script = """
                set -e
                echo '$(test_cpp)' > test.cpp
                echo '$(main_cpp)' > main.cpp
                echo '$(main_c)' > main.c
                # Make sure setting `CCACHE` doesn't affect the compiler wrappers.
                export CCACHE=pwned
                export USE_CCACHE=true
                # Build object file
                $(compiler) $(needfpic) -Werror -std=c++11 -c test.cpp -o test.o
                # Link shared library
                $(linker) -shared test.o -o libtest.\${dlext}
                # Build and link program with object file
                $(compiler) $(needfpic) -Werror -std=c++11 -c main.cpp -o main.o
                # Link main program with test object file
                $(linker) -o main main.o test.o
                # Link main program with shared library
                $(linker) -o main main.o -L. -ltest

                # Also make sure we can link to libtest (which may link to
                # libstdc++) with gcc (as in the C compiler).
                gcc -o main_c main.c -ltest -L.
                """
            cmd = `/bin/bash -c "$(test_script)"`
            @test run(ur, cmd, iobuff; tee_stream=devnull)
            seekstart(iobuff)
            # Make sure `iobuff` contains only the input command, no other text
            is_broken = (compiler == "g++" && Sys.isapple(platform) && arch(platform) == "x86_64") # This gets fixed by using GCC7 or up
            @test readchomp(iobuff) == string(cmd) broken=is_broken
        end
    end

    # This tests that compilers for all Intel Linux platforms can build simple
    # C, C++, Fortran programs that we can also run
    @testset "Compilation and running" begin
        platforms = filter(p -> Sys.islinux(p) && proc_family(p) == "intel", supported_platforms())

        @testset "C - $(platform)" for platform in platforms
            mktempdir() do dir
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
        end

        @testset "C and link to quadmath - $(platform)" for platform in platforms
            mktempdir() do dir
                # Use a recent GCC with libgfortran5
                options = (preferred_gcc_version=v"9", compilers=[:c])
                shards = choose_shards(platform; options...)
                concrete_platform = get_concrete_platform(platform, shards)
                prefix = setup_workspace(
                    dir,
                    [],
                    concrete_platform,
                    default_host_platform;
                )
                # Install `MPICH_jll` in the `${prefix}` to make sure we can link to
                # libquadmath without problems, see
                # https://github.com/JuliaPackaging/BinaryBuilderBase.jl/pull/157#issuecomment-879263820
                version = VERSION≥v"1.9.0-" ? v"3.4.2+0" : v"3.4.2" # From Julia v1.9, JLLs need to specify the build number
                artifact_paths =
                    setup_dependencies(prefix,
                                       [PackageSpec(; name="MPICH_jll", version)],
                                       concrete_platform, verbose=false)
                ur = preferred_runner()(prefix.path;
                                        platform=concrete_platform,
                                        shards = shards,
                                        options...)
                iobuff = IOBuffer()
                test_c = """
                #include <stdio.h>
                int main() {
                    printf("Hello World!\\n");
                    return 0;
                }
                """
                test_script = """
                set -e
                echo '$(test_c)' > test.c
                # Make sure we can compile successfully also when linking to libmpifort
                cc -o test test.c -L\${libdir} -lmpifort -lquadmath
                ./test
                """
                cmd = `/bin/bash -c "$(test_script)"`
                if arch(platform) == "i686" && libc(platform) == "musl"
                    # We can't run this program for this platform
                    @test_broken run(ur, cmd, iobuff; tee_stream=devnull)
                else
                    @test run(ur, cmd, iobuff; tee_stream=devnull)
                    seekstart(iobuff)
                    # Test that we get the output we expect
                    @test endswith(readchomp(iobuff), "Hello World!")
                end
                cleanup_dependencies(prefix, artifact_paths, concrete_platform)
            end
        end

        @testset "C++ - $(platform)" for platform in platforms
            mktempdir() do dir
                # Use an old GCC with libgfortran3
                options = (preferred_gcc_version=v"4", compilers=[:c])
                shards = choose_shards(platform; options...)
                concrete_platform = get_concrete_platform(platform, shards)
                prefix = setup_workspace(
                    dir,
                    [],
                    concrete_platform,
                    default_host_platform;
                )
                # Install `CompilerSupportLibraries_jll` v0.5.0 in the `${prefix}` to make
                # sure it doesn't break compilation of the program for i686-linux-gnu, see
                # https://github.com/JuliaPackaging/BinaryBuilderBase.jl/issues/163
                version = VERSION≥v"1.9.0-" ? v"0.5.0+0" : v"0.5.0" # From Julia v1.9, JLLs need to specify the build number
                artifact_paths =
                    setup_dependencies(prefix,
                                       [PackageSpec(; name="CompilerSupportLibraries_jll", version)],
                                       concrete_platform, verbose=false)
                ur = preferred_runner()(prefix.path;
                                        platform=concrete_platform,
                                        shards = shards,
                                        options...)
                iobuff = IOBuffer()
                test_cpp = """
                #include <iostream>
                class breakCCompiler; // Courtesy of Meson
                int main() {
                    std::cout << "Hello World!" << std::endl;
                    return 0;
                }
                """
                test_script = """
                set -e
                echo '$(test_cpp)' > test.cpp
                # Make sure we can compile successfully also when `\${libdir}` is in the
                # linker search path
                c++ -o test test.cpp -L\${libdir}
                ./test
                """
                cmd = `/bin/bash -c "$(test_script)"`
                if arch(platform) == "i686" && libc(platform) == "musl"
                    # We can't run C++ programs for this platform
                    @test_broken run(ur, cmd, iobuff; tee_stream=devnull)
                else
                    @test run(ur, cmd, iobuff; tee_stream=devnull)
                    seekstart(iobuff)
                    # Test that we get the output we expect
                    @test endswith(readchomp(iobuff), "Hello World!")
                end
                cleanup_dependencies(prefix, artifact_paths, concrete_platform)
            end
        end

        # This tests that compilers for all Intel Linux platforms can build a simple
        # Fortran program that we can also run
        @testset "Fortran - $(platform)" for platform in platforms
            mktempdir() do dir
                ur = preferred_runner()(dir; platform=platform)
                iobuff = IOBuffer()
                test_f = """
                      program hello
                          print *, "Hello World!"
                      end program
                """
                cmd = `/bin/bash -c "echo '$(test_f)' > test.f && gfortran -o test test.f && ./test"`
                if arch(platform) == "i686" && libc(platform) == "musl"
                    # We can't run Fortran programs for this platform
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
            @test readlines(iobuff)[2] == "BinaryBuilder: Cannot force an architecture via -march"

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
            lines = readlines(iobuff)
            @test lines[2] == "BinaryBuilder error: You used one or more of the unsafe flags: -Ofast, -ffast-math, -funsafe-math-optimizations"
            @test lines[3] == "This is not allowed, please remove all unsafe flags from your build script to continue."

            ur = preferred_runner()(dir; platform=platform, allow_unsafe_flags=true)
            iobuff = IOBuffer()
            @test run(ur, cmd, iobuff; tee_stream=devnull)
            seekstart(iobuff)
            @test split(String(read(iobuff)), "\n")[2] == ""
        end
    end

    @testset "macOS SDK setting" begin
        mktempdir() do dir
            platform = Platform("x86_64", "macos")
            test_script = raw"""
            set -e
            echo 'int main(void) { return 0; }' > test.c
            clang -Wall -Werror -Werror=unused-command-line-argument test.c -c -o test-clang.o
            clang -Wall -Werror -Werror=unused-command-line-argument test-clang.o -o test-clang
            otool -lV test-clang | grep sdk
            # Set `MACOSX_DEPLOYMENT_TARGET` to override the value of the SDK
            export MACOSX_DEPLOYMENT_TARGET=10.14
            gcc -Wall -Werror test.c -c -o test-gcc.o
            gcc -Wall -Werror test-gcc.o -o test-gcc
            otool -lV test-gcc | grep sdk
            """
            cmd = `/bin/bash -c "$(test_script)"`
            ur = preferred_runner()(dir; platform=platform, allow_unsafe_flags=false)
            iobuff = IOBuffer()
            @test run(ur, cmd, iobuff; tee_stream=devnull)
            seekstart(iobuff)
            lines = readlines(iobuff)
            # Make sure the SDK for this platform is set to 10.10, instead of other wrong
            # values, and that we can set `MACOSX_DEPLOYMENT_TARGET` to control the value.
            @test contains(lines[end - 1], r"^ +sdk 10\.10$")
            @test contains(lines[end], r"^ +sdk 10\.14$")
        end
    end

    @testset "Test lld usage" begin
        mktempdir() do dir
            ur = preferred_runner()(dir; platform=Platform("x86_64", "windows"), preferred_gcc_version=v"6")
            iobuff = IOBuffer()
            test_c = """
            #include <stdlib.h>
            int test(void) {
                return 0;
            }
            """
            test_script = """
                set -e
                echo '$(test_c)' > test.c
                clang -Werror -shared test.c -o libtest.\${dlext}
                """
            cmd = `/bin/bash -c "$(test_script)"`
            @test run(ur, cmd, iobuff)

            test_script = """
            set -e
            echo '$(test_c)' > test.c
            clang -Werror -v -shared test.c -o libtest.\${dlext}
            """
            iobuff = IOBuffer()
            cmd = `/bin/bash -c "$(test_script)"`
            @test run(ur, cmd, iobuff)
            seekstart(iobuff)
            @test occursin(r"ld.lld", readchomp(iobuff))
        end

        mktempdir() do dir
            ur = preferred_runner()(dir; platform=Platform("x86_64", "linux", libc="musl"), preferred_gcc_version=v"9")
            iobuff = IOBuffer()
            test_c = """
            #include <stdlib.h>
            int test(void) {
                return 0;
            }
            """
            test_script = """
                set -e
                echo '$(test_c)' > test.c
                gcc -Werror -shared test.c -fuse-ld=lld -o libtest.\${dlext}
                """
            cmd = `/bin/bash -c "$(test_script)"`
            @test run(ur, cmd, iobuff)

            test_script = """
            set -e
            echo '$(test_c)' > test.c
            gcc -Werror -v -shared test.c -fuse-ld=lld -o libtest.\${dlext}
            """
            iobuff = IOBuffer()
            cmd = `/bin/bash -c "$(test_script)"`
            @test run(ur, cmd, iobuff)
            seekstart(iobuff)
            @test occursin(r"lld", readchomp(iobuff))
        end

        mktempdir() do dir
            platform = Platform("x86_64", "linux", libc="musl")
            ur = preferred_runner()(dir; platform, preferred_gcc_version=v"9", clang_use_lld=false)
            iobuff = IOBuffer()
            test_script = raw"""
                cat $(which clang)
                """
            cmd = `/bin/bash -c "$(test_script)"`
            @test run(ur, cmd, iobuff)
            seekstart(iobuff)
            @test occursin("-fuse-ld=$(aatriplet(platform))", readchomp(iobuff))
        end

    end


end

@testset "Shards" begin
    # Run the testsuite as sanity check
    @testset "testsuite" begin
        mktempdir() do dir
            # Skip Rust tests when they are broken.  Ref:
            # https://github.com/JuliaPackaging/BinaryBuilderBase.jl/issues/395
            compilers = if !BinaryBuilderBase.use_squashfs[] && get(ENV, "BINARYBUILDER_RUNNER", "") == "unprivileged"
                [:c, :go]
            else
                [:c, :rust, :go]
            end
            ur = preferred_runner()(dir; platform=Platform("x86_64", "linux"; libc="glibc"), preferred_gcc_version=v"5", compilers)
            # Make sure the runner platform is concrete even if the requested platform isn't
            @test !isnothing(libgfortran_version(ur.platform))
            @test !isnothing(cxxstring_abi(ur.platform))
            iobuff = IOBuffer()
            test_script = raw"""
            set -e
            make -j${nproc} -sC /usr/share/testsuite install
            """
            @test run(ur, `/bin/bash -c "$(test_script)"`, iobuff)
        end
    end
    @testset "basic program" begin
        mktempdir() do dir
            compilers = [:c, :ocaml]
            ur = preferred_runner()(dir; platform=Platform("x86_64", "linux"; libc="glibc"), preferred_gcc_version=v"6", compilers)
            # Make sure the runner platform is concrete even if the requested platform isn't
            @test !isnothing(libgfortran_version(ur.platform))
            @test !isnothing(cxxstring_abi(ur.platform))
            iobuff = IOBuffer()
            test_script = raw"""
            set -e
            mkdir -p ${prefix}/bin
            echo 'let () = print_endline "hello world"' > hello.ml
            ocamlopt -o ${prefix}/bin/hello_world${exeext} hello.ml
            install_license /usr/share/licenses/MIT

            # Make sure it runs
            ${prefix}/bin/hello_world${exeext}
            """
            @test run(ur, `/bin/bash -c "$(test_script)"`, iobuff)
            seek(iobuff, 0)
            @test readlines(iobuff)[end] == "hello world"
        end
    end
end

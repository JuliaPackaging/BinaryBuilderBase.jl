using Test
using BinaryBuilderBase
using BinaryBuilderBase: platform_dlext, platform_exeext, prefer_clang
using Pkg

# @testset "Wrappers utilities" begin
#     @test nbits(Platform("i686", "linux")) == 32
#     @test nbits(Platform("x86_64", "linux"; march="avx")) == 64
#     @test nbits(Platform("armv7l", "linux")) == 32
#     @test nbits(Platform("aarch64", "linux"; cuda="10.1")) == 64
#     @test nbits(Platform("powerpc64le", "linux")) == 64
#     @test nbits(AnyPlatform()) == 64

#     @test proc_family(Platform("i686", "linux")) == "intel"
#     @test proc_family(Platform("x86_64", "linux"; march="avx")) == "intel"
#     @test proc_family(Platform("armv7l", "linux")) == "arm"
#     @test proc_family(Platform("aarch64", "linux"; cuda="10.1")) == "arm"
#     @test proc_family(Platform("powerpc64le", "linux")) == "power"
#     @test proc_family(AnyPlatform()) == "any"

#     @test platform_exeext(Platform("i686", "linux")) == ""
#     @test platform_exeext(Platform("x86_64", "freebsd")) == ""
#     @test platform_exeext(Platform("x86_64", "macos")) == ""
#     @test platform_exeext(Platform("i686", "windows")) == ".exe"
#     @test platform_exeext(Platform("x86_64", "linux"; march="avx512")) == ""

#     @test aatriplet(Platform("x86_64", "linux"; libc="glibc", libgfortran_version=v"4.0.0", march="avx", cuda="9.2")) == "x86_64-linux-gnu"

#     @test prefer_clang(Platform("x86_64", "freebsd"))
#     @test prefer_clang(Platform("aarch64", "macos"))
#     @test !prefer_clang(Platform("x86_64", "linux"))
#     @test prefer_clang(Platform("x86_64", "linux"; sanitize="memory"))
#     @test !prefer_clang(Platform("x86_64", "linux"; sanitize="thread"))
# end

# # Are we using docker? If so, test that the docker runner works...
# @testset "Runner utilities" begin
#     # Test that is_ecryptfs works for something we're certain isn't encrypted

#     if isdir("/proc") && Sys.islinux()
#         isecfs = (false, "/proc/")
#         @test_logs (:info, "Checking to see if /proc/ is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc"; verbose=true) == isecfs
#         @test_logs (:info, "Checking to see if /proc/ is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc/"; verbose=true) == isecfs
#         @test_logs (:info, "Checking to see if /proc/not_a_file is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc/not_a_file"; verbose=true) == isecfs
#     elseif Sys.islinux()
#         @test_logs (:info, "Checking to see if /proc/ is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc"; verbose=true) == (false, "/proc")
#         @test_logs (:info, "Checking to see if /proc/ is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc/"; verbose=true) == (false, "/proc/")
#         @test_logs (:info, "Checking to see if /proc/not_a_file is encrypted...") @test BinaryBuilderBase.is_ecryptfs("/proc/not_a_file"; verbose=true) == (false, "/proc/not_a_file")
#     end

#     if isa(preferred_runner(), BinaryBuilderBase.DockerRunner)
#         @testset "Docker image importing" begin
#             # First, delete the docker image, in case it already existed
#             BinaryBuilderBase.delete_docker_image()

#             # Next, import it and ensure that doesn't throw
#             rootfs = first(BinaryBuilderBase.choose_shards(platform))
#             mktempdir() do dir
#                 @test BinaryBuilderBase.import_docker_image(rootfs, dir; verbose=true) === nothing
#             end

#             # Test that deleting the docker image suceeds, now that we know
#             # it exists
#             @test BinaryBuilderBase.delete_docker_image()
#         end
#     end

#     @testset "hello world" begin
#         mktempdir() do dir
#             # Make sure we can start a shell in a runner when the bootstrap list is non-empty
#             @eval BinaryBuilderBase push!(bootstrap_list, :rootfs, :platform_support)
#             ur = preferred_runner()(dir; platform=Platform("x86_64", "linux"; libc="musl"))
#             iobuff = IOBuffer()
#             @test run(ur, `/bin/bash -c "echo test"`, iobuff)
#             seek(iobuff, 0)
#             # Test that we get the output we expect (e.g. the second line is `test`)
#             @test readlines(iobuff)[2] == "test"
#             # Restore empty bootstrap list
#             @eval BinaryBuilderBase empty!(bootstrap_list)
#         end
#     end

#     @testset "run_interactive" begin
#         platform = default_host_platform
#         io = IOBuffer()
#         @test run_interactive(preferred_runner()(mktempdir(); platform), `/bin/bash -c "echo hello world"`, stdout=io)
#         s = String(take!(io))
#         @test s == "hello world\n"
#         # Make sure that `run_interactive` consistently throws an error when the process fails,
#         # whatever is the type of `stdout`, or it consistently ignores failures if so requested.
#         # Ref: https://github.com/JuliaPackaging/BinaryBuilderBase.jl/pull/201#issuecomment-1003192121
#         cmd = `/bin/bash -c "false"`
#         @test_throws ProcessFailedException run_interactive(preferred_runner()(mktempdir(); platform), cmd)
#         @test_throws ProcessFailedException run_interactive(preferred_runner()(mktempdir(); platform), cmd; stdout=IOBuffer())
#         cmd = Cmd(`/bin/bash -c "false"`; ignorestatus=true)
#         @test !run_interactive(preferred_runner()(mktempdir(); platform), cmd)
#         @test !run_interactive(preferred_runner()(mktempdir(); platform), cmd; stdout=IOBuffer())
#     end

#     if lowercase(get(ENV, "BINARYBUILDER_FULL_SHARD_TEST", "false")) == "true"
#         @info("Beginning full shard test... (this can take a while)")
#         platforms = supported_platforms()
#     else
#         platforms = (default_host_platform,)
#     end

#     # Checks that the wrappers provide the correct C++ string ABI
#     @testset "Compilation - C++ string ABI" begin
#         mktempdir() do dir
#             # Host is x86_64-linux-musl-cxx11 and target is x86_64-linux-musl-cxx03
#             ur = preferred_runner()(dir; platform=Platform("x86_64", "linux"; libc="musl", cxxstring_abi="cxx03"), preferred_gcc_version=v"5")
#             iobuff = IOBuffer()
#             test_script = raw"""
#             set -e

#             # Building for the target uses C++03 string ABI
#             echo 'int main() {return 0;}' | SUPER_VERBOSE=1 ${CC} -x c - 2>&1 | grep -- "-D_GLIBCXX_USE_CXX11_ABI=0"

#             # Building for the host uses C++11 string ABI
#             echo 'int main() {return 0;}' | SUPER_VERBOSE=1 ${HOSTCC} -x c - 2>&1 | grep -v -- "-D_GLIBCXX_USE_CXX11_ABI=0"
#             """
#             @test run(ur, `/bin/bash -c "$(test_script)"`, iobuff; tee_stream=devnull)
#         end
#     end

#     # This tests only that compilers for all platforms can build and link simple C code
#     @testset "Compilation - $(platform) - $(compiler)" for platform in platforms, compiler in ("cc", "gcc", "clang")
#         mktempdir() do dir
#             # if compiler == "clang"
#             #     ur = preferred_runner()(dir; platform=platform, preferred_gcc_version=v"5") #TODO: Fix CI disk size issues to allow this
#             # else
#             #     ur = preferred_runner()(dir; platform=platform)
#             # end
#             ur = preferred_runner()(dir; platform=platform)
#             iobuff = IOBuffer()
#             test_c = """
#                 #include <stdlib.h>
#                 int test(void) {
#                     return 0;
#                 }
#                 """
#             main_c = """
#             int test(void);
#             int main(void) {
#                 return test();
#             }
#             """
#             test_script = """
#                 set -e
#                 echo '$(test_c)' > test.c
#                 echo '$(main_c)' > main.c
#                 # Build object file
#                 $(compiler) -Werror -c test.c -o test.o
#                 # Build shared library
#                 $(compiler) -Werror -shared test.c -o libtest.\${dlext}
#                 # Build and link program with object file
#                 $(compiler) -Werror -o main main.c test.o
#                 # Build and link program with shared library
#                 $(compiler) -Werror -o main main.c -L. -ltest
#                 """
#             cmd = `/bin/bash -c "$(test_script)"`
#             @test run(ur, cmd, iobuff)
#             seekstart(iobuff)
#             # Make sure `iobuff` contains only the input command, no other text
#             @test readchomp(iobuff) == string(cmd)
#         end
#     end

#     # This tests only that compilers for all platforms can build and link simple C++ code
#     @testset "Compilation - $(platform) - $(compiler)" for platform in platforms, compiler in ("c++", "g++", "clang++")
#         mktempdir() do dir
#             ur = preferred_runner()(dir; platform=platform)
#             iobuff = IOBuffer()
#             needfpic = Sys.iswindows(platform) ? "" : "-fPIC"
#             test_cpp = """
#                 #include <complex>
#                 std::complex<double> add(std::complex<double> a, std::complex<double> b) {
#                     return a + b;
#                 }
#                 """
#             main_cpp = """
#                 #include <complex>
#                 std::complex<double> add(std::complex<double> a, std::complex<double> b);
#                 int main(void) {
#                     std::complex<double> z3 = add(std::complex<double>(1.,2.),std::complex<double>(4.,2.));
#                     return 0;
#                 }
#             """
#             test_script = """
#                 set -e
#                 echo '$(test_cpp)' > test.cpp
#                 echo '$(main_cpp)' > main.cpp
#                 # Build object file
#                 $(compiler) -Werror -std=c++11 -c test.cpp -o test.o
#                 # Build shared library
#                 $(compiler) -Werror -std=c++11 $(needfpic) -shared test.cpp -o libtest.\${dlext}
#                 # Build and link program with object file
#                 $(compiler) -Werror -std=c++11 -o main main.cpp test.o
#                 # Build and link program with shared library
#                 $(compiler) -Werror -std=c++11 -o main main.cpp -L. -ltest
#                 """
#             cmd = `/bin/bash -c "$(test_script)"`
#             @test run(ur, cmd, iobuff; tee_stream=devnull)
#             seekstart(iobuff)
#             # Make sure `iobuff` contains only the input command, no other text
#             is_broken = (compiler == "g++" && Sys.isapple(platform) && arch(platform) == "x86_64") # This gets fixed by using GCC7 or up
#             @test readchomp(iobuff) == string(cmd) broken=is_broken
#         end
#     end

#     # This tests that compilers for all Intel Linux platforms can build simple
#     # C, C++, Fortran programs that we can also run
#     @testset "Compilation and running" begin
#         platforms = filter(p -> Sys.islinux(p) && proc_family(p) == "intel", supported_platforms())

#         @testset "C - $(platform)" for platform in platforms
#             mktempdir() do dir
#                 ur = preferred_runner()(dir; platform=platform)
#                 iobuff = IOBuffer()
#                 test_c = """
#                 #include <stdio.h>
#                 int main() {
#                     printf("Hello World!\\n");
#                     return 0;
#                 }
#                 """
#                 cmd = `/bin/bash -c "echo '$(test_c)' > test.c && cc -o test test.c && ./test"`
#                 @test run(ur, cmd, iobuff; tee_stream=devnull)
#                 seekstart(iobuff)
#                 # Test that we get the output we expect
#                 @test endswith(readchomp(iobuff), "Hello World!")
#             end
#         end

#         @testset "C and link to quadmath - $(platform)" for platform in platforms
#             mktempdir() do dir
#                 # Use a recent GCC with libgfortran5
#                 options = (preferred_gcc_version=v"9", compilers=[:c])
#                 shards = choose_shards(platform; options...)
#                 concrete_platform = get_concrete_platform(platform, shards)
#                 prefix = setup_workspace(
#                     dir,
#                     [],
#                     concrete_platform,
#                     default_host_platform;
#                 )
#                 # Install `MPICH_jll` in the `${prefix}` to make sure we can link to
#                 # libquadmath without problems, see
#                 # https://github.com/JuliaPackaging/BinaryBuilderBase.jl/pull/157#issuecomment-879263820
#                 version = VERSION≥v"1.9.0-" ? v"3.4.2+0" : v"3.4.2" # From Julia v1.9, JLLs need to specify the build number
#                 artifact_paths =
#                     setup_dependencies(prefix,
#                                        [PackageSpec(; name="MPICH_jll", version)],
#                                        concrete_platform, verbose=false)
#                 ur = preferred_runner()(prefix.path;
#                                         platform=concrete_platform,
#                                         shards = shards,
#                                         options...)
#                 iobuff = IOBuffer()
#                 test_c = """
#                 #include <stdio.h>
#                 int main() {
#                     printf("Hello World!\\n");
#                     return 0;
#                 }
#                 """
#                 test_script = """
#                 set -e
#                 echo '$(test_c)' > test.c
#                 # Make sure we can compile successfully also when linking to libmpifort
#                 cc -o test test.c -L\${libdir} -lmpifort -lquadmath
#                 ./test
#                 """
#                 cmd = `/bin/bash -c "$(test_script)"`
#                 if arch(platform) == "i686" && libc(platform) == "musl"
#                     # We can't run this program for this platform
#                     @test_broken run(ur, cmd, iobuff; tee_stream=devnull)
#                 else
#                     @test run(ur, cmd, iobuff; tee_stream=devnull)
#                     seekstart(iobuff)
#                     # Test that we get the output we expect
#                     @test endswith(readchomp(iobuff), "Hello World!")
#                 end
#                 cleanup_dependencies(prefix, artifact_paths, concrete_platform)
#             end
#         end

#         @testset "C++ - $(platform)" for platform in platforms
#             mktempdir() do dir
#                 # Use an old GCC with libgfortran3
#                 options = (preferred_gcc_version=v"4", compilers=[:c])
#                 shards = choose_shards(platform; options...)
#                 concrete_platform = get_concrete_platform(platform, shards)
#                 prefix = setup_workspace(
#                     dir,
#                     [],
#                     concrete_platform,
#                     default_host_platform;
#                 )
#                 # Install `CompilerSupportLibraries_jll` v0.5.0 in the `${prefix}` to make
#                 # sure it doesn't break compilation of the program for i686-linux-gnu, see
#                 # https://github.com/JuliaPackaging/BinaryBuilderBase.jl/issues/163
#                 version = VERSION≥v"1.9.0-" ? v"0.5.0+0" : v"0.5.0" # From Julia v1.9, JLLs need to specify the build number
#                 artifact_paths =
#                     setup_dependencies(prefix,
#                                        [PackageSpec(; name="CompilerSupportLibraries_jll", version)],
#                                        concrete_platform, verbose=false)
#                 ur = preferred_runner()(prefix.path;
#                                         platform=concrete_platform,
#                                         shards = shards,
#                                         options...)
#                 iobuff = IOBuffer()
#                 test_cpp = """
#                 #include <iostream>
#                 class breakCCompiler; // Courtesy of Meson
#                 int main() {
#                     std::cout << "Hello World!" << std::endl;
#                     return 0;
#                 }
#                 """
#                 test_script = """
#                 set -e
#                 echo '$(test_cpp)' > test.cpp
#                 # Make sure we can compile successfully also when `\${libdir}` is in the
#                 # linker search path
#                 c++ -o test test.cpp -L\${libdir}
#                 ./test
#                 """
#                 cmd = `/bin/bash -c "$(test_script)"`
#                 if arch(platform) == "i686" && libc(platform) == "musl"
#                     # We can't run C++ programs for this platform
#                     @test_broken run(ur, cmd, iobuff; tee_stream=devnull)
#                 else
#                     @test run(ur, cmd, iobuff; tee_stream=devnull)
#                     seekstart(iobuff)
#                     # Test that we get the output we expect
#                     @test endswith(readchomp(iobuff), "Hello World!")
#                 end
#                 cleanup_dependencies(prefix, artifact_paths, concrete_platform)
#             end
#         end

#         # This tests that compilers for all Intel Linux platforms can build a simple
#         # Fortran program that we can also run
#         @testset "Fortran - $(platform)" for platform in platforms
#             mktempdir() do dir
#                 ur = preferred_runner()(dir; platform=platform)
#                 iobuff = IOBuffer()
#                 test_f = """
#                       program hello
#                           print *, "Hello World!"
#                       end program
#                 """
#                 cmd = `/bin/bash -c "echo '$(test_f)' > test.f && gfortran -o test test.f && ./test"`
#                 if arch(platform) == "i686" && libc(platform) == "musl"
#                     # We can't run Fortran programs for this platform
#                     @test_broken run(ur, cmd, iobuff; tee_stream=devnull)
#                 else
#                     @test run(ur, cmd, iobuff; tee_stream=devnull)
#                     seekstart(iobuff)
#                     # Test that we get the output we expect
#                     @test endswith(readchomp(iobuff), "Hello World!")
#                 end
#             end
#         end
#     end

#     @testset "Locking microarchitecture" begin
#         mktempdir() do dir
#             platform = Platform("x86_64", "linux"; libc="musl")
#             cmd = `/bin/bash -c "echo 'int main() {return 0;}' | cc -x c -march=native -"`
#             ur = preferred_runner()(dir; platform=platform, lock_microarchitecture=true)
#             iobuff = IOBuffer()
#             @test !run(ur, cmd, iobuff; tee_stream=devnull)
#             seekstart(iobuff)
#             @test readlines(iobuff)[2] == "BinaryBuilder: Cannot force an architecture via -march"

#             ur = preferred_runner()(dir; platform=platform, lock_microarchitecture=false)
#             iobuff = IOBuffer()
#             @test run(ur, cmd, iobuff; tee_stream=devnull)
#             seekstart(iobuff)
#             @test split(String(read(iobuff)), "\n")[2] == ""
#         end
#     end

#     @testset "Unsafe flags" begin
#         mktempdir() do dir
#             platform = Platform("x86_64", "linux"; libc="musl")
#             cmd = `/bin/bash -c "echo 'int main() {return 0;}' | cc -x c -Ofast -"`
#             ur = preferred_runner()(dir; platform=platform, allow_unsafe_flags=false)
#             iobuff = IOBuffer()
#             @test !run(ur, cmd, iobuff; tee_stream=devnull)
#             seekstart(iobuff)
#             lines = readlines(iobuff)
#             @test lines[2] == "BinaryBuilder: You used one or more of the unsafe flags: -Ofast, -ffast-math, -funsafe-math-optimizations"
#             @test lines[3] == "Please repent."

#             ur = preferred_runner()(dir; platform=platform, allow_unsafe_flags=true)
#             iobuff = IOBuffer()
#             @test run(ur, cmd, iobuff; tee_stream=devnull)
#             seekstart(iobuff)
#             @test split(String(read(iobuff)), "\n")[2] == ""
#         end
#     end

#     @testset "macOS SDK setting" begin
#         mktempdir() do dir
#             platform = Platform("x86_64", "macos")
#             test_script = raw"""
#             set -e
#             prog='int main(void) { return 0; }'
#             echo "${prog}" | clang -x c - -o test-clang
#             otool -lV test-clang | grep sdk
#             # Set `MACOSX_DEPLOYMENT_TARGET` to override the value of the SDK
#             export MACOSX_DEPLOYMENT_TARGET=10.14
#             echo "${prog}" | gcc -x c - -o test-gcc
#             otool -lV test-gcc | grep sdk
#             """
#             cmd = `/bin/bash -c "$(test_script)"`
#             ur = preferred_runner()(dir; platform=platform, allow_unsafe_flags=false)
#             iobuff = IOBuffer()
#             @test run(ur, cmd, iobuff; tee_stream=devnull)
#             seekstart(iobuff)
#             lines = readlines(iobuff)
#             # Make sure the SDK for this platform is set to 10.10, instead of other wrong
#             # values, and that we can set `MACOSX_DEPLOYMENT_TARGET` to control the value.
#             @test contains(lines[end - 1], r"^ +sdk 10\.10$")
#             @test contains(lines[end], r"^ +sdk 10\.14$")
#         end
#     end
# end

@testset "Shards" begin
    # Run the testsuite as sanity check
    @testset "testsuite" begin
        mktempdir() do dir
            ur = preferred_runner()(dir; platform=Platform("x86_64", "linux"; libc="glibc"), preferred_gcc_version=v"5", compilers=[:c, :rust, :go])
            # Make sure the runner platform is concrete even if the requested platform isn't
            @test !isnothing(libgfortran_version(ur.platform))
            @test !isnothing(cxxstring_abi(ur.platform))
            iobuff = IOBuffer()
            test_script = raw"""
            set -e
            make -j${nproc} -sC /usr/share/testsuite install
            """
            @test @show run(ur, `/bin/bash -c "$(test_script)"`, iobuff; tee_stream=devnull)
        end
    end
end

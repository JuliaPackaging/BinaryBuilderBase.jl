using Test
using Pkg.BinaryPlatforms
import Libdl
using BinaryBuilderBase
using BinaryBuilderBase: template

# The platform we're running on
const platform = platform_key_abi()

@testset "Products" begin
    @test template(raw"$libdir/foo-$arch/$nbits/bar-$target", Windows(:x86_64)) ==
        "bin/foo-x86_64/64/bar-x86_64-w64-mingw32"
    @test template(raw"$target/$nbits/$arch/$libdir", Linux(:x86_64; libc = :musl)) ==
        "x86_64-linux-musl/64/x86_64/lib"

    lp = LibraryProduct("libfakechroot", :libfakechroot, "lib/fakechroot")
    @test lp.libnames ==  ["libfakechroot"]
    @test lp.dir_paths == ["lib/fakechroot"]
    ep = ExecutableProduct("fooify", :fooify, "bin/foo_inc")
    @test ep.binnames ==  ["fooify"]

    @test_throws ErrorException LibraryProduct("sin", :sin)
    @test_throws ErrorException ExecutableProduct("convert", :convert)
    @test_throws ErrorException FileProduct("open", :open)

    # Test sorting of products....
    @test sort([LibraryProduct("libbar", :libbar), ExecutableProduct("foo", :foo), FrameworkProduct("buzz", :buzz)]) ==
        [FrameworkProduct("buzz", :buzz), ExecutableProduct("foo", :foo), LibraryProduct("libbar", :libbar)]
    # ...and products info
    p1 = LibraryProduct(["libchafa"], :libchafa, ) => Dict("soname" => "libchafa.so.0","path" => "lib/libchafa.so")
    p2 = ExecutableProduct(["chafa"], :chafa, ) => Dict("path" => "bin/chafa")
    products_info = Dict{Product,Any}(p1, p2)
    @test sort(products_info) == [p2, p1]

    temp_prefix() do prefix
        # Test that basic satisfication is not guaranteed
        e_path = joinpath(bindir(prefix), "fooifier")
        l_path = joinpath(last(libdirs(prefix)), "libfoo.$(Libdl.dlext)")
        e = ExecutableProduct("fooifier", :fooifier)
        ef = FileProduct(joinpath("bin", "fooifier"), :fooifier)
        l = LibraryProduct("libfoo", :libfoo)
        lf = FileProduct(l_path, :libfoo)

        @test @test_logs (:info, r"does not exist") !satisfied(e, prefix; verbose=true)
        @test @test_logs (:info, r"not found") !satisfied(ef, prefix; verbose=true)
        @test @test_logs (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true)
        @test @test_logs (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true, isolate=true)
        @test @test_logs (:info, r"^FileProduct .* not found") !satisfied(lf, prefix; verbose=true)

        # Test that simply creating a file that is not executable doesn't
        # satisfy an Executable Product (and say it's on Linux so it doesn't
        # complain about the lack of an .exe extension)
        mkpath(bindir(prefix))
        touch(e_path)
        @test @test_logs (:info, r"^FileProduct .* found at") satisfied(ef, prefix; verbose=true)
        @static if !Sys.iswindows()
            # Windows doesn't care about executable bit, grumble grumble
            @test @test_logs (:info, r"is not executable") (:info, r"does not exist") !satisfied(e, prefix; verbose=true, platform=Linux(:x86_64))
        end

        # Make it executable and ensure this does satisfy the Executable
        chmod(e_path, 0o777)
        @test @test_logs (:info, r"matches our search criteria") satisfied(e, prefix; verbose=true, platform=Linux(:x86_64))

        # Remove it and add a `$(path).exe` version to check again, this
        # time saying it's a Windows executable
        Base.rm(e_path; force=true)
        touch("$(e_path).exe")
        chmod("$(e_path).exe", 0o777)
        @test locate(e, prefix; platform=Windows(:x86_64)) == "$(e_path).exe"

        # Test that simply creating a library file doesn't satisfy it if we are
        # testing something that matches the current platform's dynamic library
        # naming scheme, because it must be `dlopen()`able.
        mkpath(last(libdirs(prefix)))
        touch(l_path)
        @test @test_logs (:info, r"^FileProduct .* found at") satisfied(lf, prefix; verbose=true)
        @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") (:info, r"cannot be dlopen'ed") (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true)
        @test @test_logs (:info, r"^FileProduct .* found at") satisfied(lf, prefix; verbose=true, isolate=true)
        @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") (:info, r"cannot be dlopen'ed") (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true, isolate=true)

        # But if it is from a different platform, simple existence will be
        # enough to satisfy a LibraryProduct
        @static if Sys.iswindows()
            p = Linux(:x86_64)
            mkpath(last(libdirs(prefix, p)))
            l_path = joinpath(last(libdirs(prefix, p)), "libfoo.so")
            touch(l_path)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(l, prefix; verbose=true, platform=p)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(l, prefix; verbose=true, platform=p, isolate=true)

            # Check LibraryProduct objects with explicit directory paths
            ld = LibraryProduct("libfoo", :libfoo)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(ld, prefix; verbose=true, platform=p)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(ld, prefix; verbose=true, platform=p, isolate=true)
        else
            p = Windows(:x86_64)
            mkpath(last(libdirs(prefix, p)))
            l_path = joinpath(last(libdirs(prefix, p)), "libfoo.dll")
            touch(l_path)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(l, prefix; verbose=true, platform=p)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(l, prefix; verbose=true, platform=p, isolate=true)

            # Check LibraryProduct objects with explicit directory paths
            ld = LibraryProduct("libfoo", :libfoo)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(ld, prefix; verbose=true, platform=p)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(ld, prefix; verbose=true, platform=p, isolate=true)
        end
    end

    # Ensure that the test suite thinks that these libraries are foreign
    # so that it doesn't try to `dlopen()` them:
    foreign_platform = if platform == Linux(:aarch64)
        # Arbitrary architecture that is not dlopen()'able
        Linux(:powerpc64le)
    else
        # If we're not Linux(:aarch64), then say the libraries are
        Linux(:aarch64)
    end

    # Test for valid library name permutations
    for ext in ["so", "so.1", "so.1.2", "so.1.2.3"]
        temp_prefix() do prefix
            l_path = joinpath(last(libdirs(prefix, foreign_platform)), "libfoo.$ext")
            l = LibraryProduct("libfoo", :libfoo)
            mkdir(dirname(l_path))
            touch(l_path)
            @test @test_logs (:info, r"^Found a valid") (:info, r"matches our search criteria") satisfied(l, prefix; verbose=true, platform=foreign_platform)
        end
    end

    # Test for invalid library name permutations
    for ext in ["1.so", "so.1.2.3a", "so.1.a"]
        temp_prefix() do prefix
            l_path = joinpath(last(libdirs(prefix, foreign_platform)), "libfoo.$ext")
            l = LibraryProduct("libfoo", :libfoo)
            mkdir(dirname(l_path))
            touch(l_path)
            if ext == "1.so"
                @test @test_logs (:info, r"^Found a valid") (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true, platform=foreign_platform)
            else
                @test @test_logs (:info, r"^Could not locate") !satisfied(l, prefix; verbose=true, platform=foreign_platform)
            end
        end
    end

    # Test for proper repr behavior
    temp_prefix() do prefix
        l = LibraryProduct("libfoo", :libfoo)
        @test repr(l) == "LibraryProduct($(repr(["libfoo"])), :libfoo)"
        l = LibraryProduct(["libfoo", "libfoo2"], :libfoo)
        @test repr(l) == "LibraryProduct($(repr(["libfoo", "libfoo2"])), :libfoo)"

        e = ExecutableProduct("fooifier", :fooifier)
        @test repr(e) == "ExecutableProduct([\"fooifier\"], :fooifier)"
        e = ExecutableProduct("fooifier", :fooifier, "bin/qux")
        @test repr(e) == "ExecutableProduct([\"fooifier\"], :fooifier, \"bin/qux\")"

        f = FileProduct(joinpath("etc", "fooifier"), :foo_conf)
        @test repr(f) == "FileProduct([$(repr(joinpath("etc", "fooifier")))], :foo_conf)"

        f = FileProduct(joinpath(prefix, "etc", "foo.conf"), :foo_conf)
        @test repr(f) == "FileProduct([$(repr(joinpath(prefix, "etc", "foo.conf")))], :foo_conf)"
    end

    # Test that FileProduct's can have `${target}` within their paths:
    temp_prefix() do prefix
        multilib_dir = joinpath(prefix, "foo", triplet(platform))
        mkpath(multilib_dir)
        touch(joinpath(multilib_dir, "bar"))

        for path in ("foo/\$target/bar", "foo/\${target}/bar")
            f = FileProduct(path, :bar)
            @test  @test_logs (:info, r"^FileProduct .* found at") satisfied(f, prefix; verbose=true, platform=platform)
        end
    end
end

@testset "Dlopen flags" begin
    lp = LibraryProduct("libfoo2", :libfoo2; dlopen_flags=[:RTLD_GLOBAL, :RTLD_NOLOAD])
    @test lp.dlopen_flags == [:RTLD_GLOBAL, :RTLD_NOLOAD]
    fp = FrameworkProduct("libfoo2", :libfoo2; dlopen_flags=[:RTLD_GLOBAL, :RTLD_NOLOAD])
    @test fp.libraryproduct.dlopen_flags == [:RTLD_GLOBAL, :RTLD_NOLOAD]
    for p in (lp, fp)
        flag_str = BinaryBuilderBase.dlopen_flags_str(p)
        @test flag_str == "RTLD_GLOBAL | RTLD_NOLOAD"
        @test Libdl.eval(Meta.parse(flag_str)) == (Libdl.RTLD_NOLOAD | Libdl.RTLD_GLOBAL)
    end
end

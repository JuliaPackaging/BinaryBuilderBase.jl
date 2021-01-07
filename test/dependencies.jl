using Test
using Pkg, Base.BinaryPlatforms
using BinaryBuilderBase
using BinaryBuilderBase: getname, getpkg, dependencify
using JSON

# Define equality between dependencies, in order to carry out the tests below
Base.:(==)(a::AbstractDependency, b::AbstractDependency) = getpkg(a) == getpkg(b)

function with_temp_project(f::Function)
    mktempdir() do dir
        Pkg.activate(dir) do
            f(dir)
        end
    end
end

@testset "Dependencies" begin
    name = "Foo_jll"
    dep = Dependency(PackageSpec(; name = name))
    @test Dependency(name) == dep
    @test getname(dep) == name
    @test getname(PackageSpec(; name = name)) == name
    @test getpkg(dep) == PackageSpec(; name = name)

    build_version = v"1.2.3"
    dep_buildver = Dependency(PackageSpec(; name = name), build_version)
    @test Dependency(name, build_version) == dep_buildver
    @test getname(dep_buildver) == name
    @test getpkg(dep_buildver) == PackageSpec(; name = name, version = build_version)

    build_name = "Foo_headers_jll"
    build_dep = BuildDependency(PackageSpec(; name = build_name))
    @test BuildDependency(build_name) == build_dep
    @test getname(build_dep) == build_name
    @test getname(PackageSpec(; name = build_name)) == build_name
    @test getpkg(build_dep) == PackageSpec(; name = build_name)

    @testset "JSON (de)serialization" begin
        jdep = JSON.lower(dep)
        @test jdep == Dict("type" => "dependency", "name" => name, "uuid" => nothing, "version-major" => 0x0, "version-minor" => 0x0, "version-patch" => 0x0)
        @test dependencify(jdep) == dep

        jdep_buildver = JSON.lower(dep_buildver)
        @test jdep_buildver == Dict("type" => "dependency", "name" => name, "uuid" => nothing, "version-major" => 0x0, "version-minor" => 0x0, "version-patch" => 0x0)
        # the build_version is currently not serialized, so the following test fails
        @test_broken dependencify(jdep_buildver) == dep_buildver

        jbuild_dep = JSON.lower(build_dep)
        @test jbuild_dep == Dict("type" => "builddependency", "name" => build_name, "uuid" => nothing, "version-major" => 0x0, "version-minor" => 0x0, "version-patch" => 0x0)
        @test dependencify(jbuild_dep) == build_dep

        full_dep = Dependency(PackageSpec(; name = "Baz_jll", uuid = "00000000-1111-2222-3333-444444444444", version = "3.1.4"))
        jfull_dep = JSON.lower(full_dep)
        @test jfull_dep == Dict("type" => "dependency", "name" => "Baz_jll", "uuid" => "00000000-1111-2222-3333-444444444444", "version-major" => 0x3, "version-minor" => 0x1, "version-patch" => 0x4)
        @test dependencify(jfull_dep) == full_dep
        @test_throws ErrorException dependencify(Dict("type" => "git"))
    end

    @testset "Setup" begin
        with_temp_project() do dir
            prefix = Prefix(dir)
            dependencies = [
                Dependency("Zlib_jll")
            ]
            platform = HostPlatform()
            ap = @test_logs setup_dependencies(prefix, getpkg.(dependencies), platform)
            @test "libz." * platform_dlext(platform) in readdir(last(libdirs(Prefix(joinpath(dir, "destdir")))))
            @test "zlib.h" in readdir(joinpath(dir, "destdir", "include"))
            @test readdir(joinpath(dir, "destdir", "logs")) == ["Zlib.log.gz"]

            # Make sure the directories are emptied by `cleanup_dependencies`
            @test_nowarn cleanup_dependencies(prefix, ap)
            @test readdir(joinpath(dir, "destdir", "include")) == []
            @test readdir(joinpath(dir, "destdir", "logs")) == []
        end

        # Setup a dependency of a JLL package which is also a standard library
        with_temp_project() do dir
            prefix = Prefix(dir)
            dependencies = [
                Dependency("LibCURL_jll")
            ]
            platform = HostPlatform()
            ap = @test_logs setup_dependencies(prefix, getpkg.(dependencies), platform)
            @test "libcurl." * platform_dlext(platform) in readdir(last(libdirs(Prefix(joinpath(dir, "destdir")))))
            @test "curl.h" in readdir(joinpath(dir, "destdir", "include", "curl"))
            @test "libssh2." * platform_dlext(platform) in readdir(last(libdirs(Prefix(joinpath(dir, "destdir")))))

            # Make sure the directories are emptied by `cleanup_dependencies`
            @test_nowarn cleanup_dependencies(prefix, ap)
            # This shuld be empty, but the `curl/` directory is left here, empty
            @test_broken readdir(joinpath(dir, "destdir", "include")) == []
            @test readdir(joinpath(dir, "destdir", "logs")) == []
        end

        # Setup a dependency that doesn't have a mapping for the given platform
        with_temp_project() do dir
            prefix = Prefix(dir)
            dependencies = [
                Dependency("LibOSXUnwind_jll")
            ]
            platform = Platform("i686", "linux"; libc="musl")
            @test_logs (:warn, r"Dependency LibOSXUnwind_jll does not have a mapping for artifact LibOSXUnwind for platform i686-linux-musl") begin
                setup_dependencies(prefix, getpkg.(dependencies), platform)
            end
            @test "destdir" ∉ readdir(joinpath(dir))
        end

        # Test setup of dependencies that depend on the Julia version
        with_temp_project() do dir
            prefix = Prefix(dir)
            dependencies = [Dependency("GMP_jll")]
            platform = Platform("x86_64", "linux"; julia_version=v"1.5")

            # Test that a particular version of GMP is installed
            ap = @test_logs setup_dependencies(prefix, getpkg.(dependencies), platform)
            @test isfile(joinpath(dir, "destdir", "lib", "libgmp.so.10.3.2"))
        end

        # Next, test on Julia v1.6
        with_temp_project() do dir
            prefix = Prefix(dir)
            dependencies = [Dependency("GMP_jll")]
            platform = Platform("x86_64", "linux"; julia_version=v"1.6")

            # Test that a particular version of GMP is installed
            ap = @test_logs setup_dependencies(prefix, getpkg.(dependencies), platform)
            @test isfile(joinpath(dir, "destdir", "lib", "libgmp.so.10.4.0"))
        end

        # Next, build a set of dependencies that are not instantiatable as-is:
        with_temp_project() do dir
            prefix = Prefix(dir)
            dependencies = [
                 Dependency("GMP_jll", v"6.1.2"),
                 Dependency("MPFR_jll",v"4.1.0"),
            ]

            # Test that this is not instantiatable with either Julia v1.5 or v1.6
            platform = Platform("x86_64", "linux"; julia_version=v"1.5")
            ap = @test_throws Pkg.Resolve.ResolverError setup_dependencies(prefix, getpkg.(dependencies), platform)
            platform = Platform("x86_64", "linux"; julia_version=v"1.6")
            ap = @test_throws Pkg.Resolve.ResolverError setup_dependencies(prefix, getpkg.(dependencies), platform)

            # If we don't give a `julia_version`, then we are FULLY UNSHACKLED.
            platform = Platform("x86_64", "linux")
            ap = @test_logs setup_dependencies(prefix, getpkg.(dependencies), platform)
            @test isfile(joinpath(dir, "destdir", "lib", "libgmp.so.10.3.2"))
            @test isfile(joinpath(dir, "destdir", "lib", "libmpfr.so.6.1.0"))
        end
    end
end

@testset "resolve_jlls" begin
    # Deps given by name::String
    dependencies = ["OpenSSL_jll",]
    @test_logs (:warn, r"use Dependency instead") begin
        truefalse, resolved_deps = resolve_jlls(dependencies)
        @test truefalse
        @test all(x->getpkg(x).uuid !== nothing, resolved_deps)
    end
    # Deps given by name::PackageSpec
    @test_logs (:warn, r"use Dependency instead") begin
        dependencies = [PackageSpec(name="OpenSSL_jll"),]
        truefalse, resolved_deps = resolve_jlls(dependencies)
        @test truefalse
        @test all(x->getpkg(x).uuid !== nothing, resolved_deps)
    end
    # Deps given by (name,uuid)::PackageSpec
    dependencies = [Dependency(PackageSpec(name="OpenSSL_jll", uuid="458c3c95-2e84-50aa-8efc-19380b2a3a95")),]
    truefalse, resolved_deps = resolve_jlls(dependencies)
    @test truefalse
    @test all(x->getpkg(x).uuid !== nothing, resolved_deps)
    # Deps given by combination of name::String, name::PackageSpec and (name,uuid)::PackageSpec
    dependencies = [
        Dependency("Zlib_jll"),
        Dependency(PackageSpec(name="Bzip2_jll")),
        Dependency(PackageSpec(name="OpenSSL_jll", uuid="458c3c95-2e84-50aa-8efc-19380b2a3a95")),
    ]
    truefalse, resolved_deps = resolve_jlls(dependencies)
    @test truefalse
    @test all(x->getpkg(x).uuid !== nothing, resolved_deps)
end

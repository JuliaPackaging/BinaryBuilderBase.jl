using Test
using Pkg, Base.BinaryPlatforms
using BinaryBuilderBase
using BinaryBuilderBase: getname, getpkg, dependencify, destdir
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
    dep = Dependency(PackageSpec(; name = name); platforms=supported_platforms(; experimental=true, exclude=!Sys.isapple))
    @test Dependency(name) == dep
    @test !is_host_dependency(dep)
    @test is_target_dependency(dep)
    @test is_build_dependency(dep)
    @test is_runtime_dependency(dep)
    @test getname(dep) == name
    @test getname(PackageSpec(; name = name)) == name
    @test getpkg(dep) == PackageSpec(; name = name)
    @test getcompat(dep) == ""

    build_version = v"1.2.3"
    dep_buildver = Dependency(PackageSpec(; name = name), build_version)
    @test Dependency(name, build_version) == dep_buildver
    @test getname(dep_buildver) == name
    @test getpkg(dep_buildver) == PackageSpec(; name = name, version = build_version)
    @test getcompat(dep_buildver) == ""

    # the same but with compat info
    dep_buildver = Dependency(PackageSpec(; name = name), build_version; compat = "~1.2", platforms=expand_cxxstring_abis(Platform("x86_64", "linux")))
    @test Dependency(name, build_version) == dep_buildver
    @test getname(dep_buildver) == name
    @test getpkg(dep_buildver) == PackageSpec(; name = name, version = build_version)
    @test getcompat(dep_buildver) == "~1.2"

    # the same but only with compat specifier
    dep_compat = Dependency(PackageSpec(; name); compat = "2, ~$(build_version)")
    @test Dependency(name, build_version) == dep_compat
    @test getname(dep_compat) == name
    @test getpkg(dep_compat) == PackageSpec(; name, version = build_version)
    @test getcompat(dep_compat) == "2, ~$(build_version)"

    # if build_version and compat don't match, an error should be thrown
    @test_throws ArgumentError Dependency(PackageSpec(; name = name), build_version, compat = "2.0")

    build_name = "Foo_headers_jll"
    build_dep = BuildDependency(PackageSpec(; name = build_name))
    @test BuildDependency(build_name) == build_dep
    @test !is_host_dependency(build_dep)
    @test is_target_dependency(build_dep)
    @test is_build_dependency(build_dep)
    @test !is_runtime_dependency(build_dep)
    @test getname(build_dep) == build_name
    @test getname(PackageSpec(; name = build_name)) == build_name
    @test getpkg(build_dep) == PackageSpec(; name = build_name)

    host_name = "Patchelf_jll"
    host_dep = HostBuildDependency(PackageSpec(; name = host_name))
    @test HostBuildDependency(host_name) == host_dep
    @test is_host_dependency(host_dep)
    @test !is_target_dependency(host_dep)
    @test is_build_dependency(host_dep)
    @test !is_runtime_dependency(host_dep)
    @test getname(host_dep) == host_name
    @test getname(PackageSpec(; name = host_name)) == host_name
    @test getpkg(host_dep) == PackageSpec(; name = host_name)

    @testset "JSON (de)serialization" begin
        jdep = JSON.lower(dep)
        @test jdep == Dict("type" => "dependency", "name" => name, "uuid" => nothing, "compat" => "", "version-major" => 0x0, "version-minor" => 0x0, "version-patch" => 0x0, "platforms" => ["x86_64-apple-darwin", "aarch64-apple-darwin"])
        @test dependencify(jdep) == dep

        jdep_buildver = JSON.lower(dep_buildver)
        @test jdep_buildver == Dict("type" => "dependency", "name" => name, "uuid" => nothing, "compat" => "~1.2", "version-major" => 0x0, "version-minor" => 0x0, "version-patch" => 0x0, "platforms" => ["x86_64-linux-gnu-cxx03", "x86_64-linux-gnu-cxx11"])
        # the build_version is currently not serialized, so the following test fails
        @test_broken dependencify(jdep_buildver) == dep_buildver

        jbuild_dep = JSON.lower(build_dep)
        @test jbuild_dep == Dict("type" => "builddependency", "name" => build_name, "uuid" => nothing, "compat" => "", "version-major" => 0x0, "version-minor" => 0x0, "version-patch" => 0x0, "platforms" => ["any"])
        @test dependencify(jbuild_dep) == build_dep

        jhost_dep = JSON.lower(host_dep)
        @test jhost_dep == Dict("type" => "hostdependency", "name" => host_name, "uuid" => nothing, "compat" => "", "version-major" => 0x0, "version-minor" => 0x0, "version-patch" => 0x0, "platforms" => ["any"])
        @test dependencify(jhost_dep) == host_dep

        full_dep = Dependency(PackageSpec(; name = "Baz_jll", uuid = "00000000-1111-2222-3333-444444444444", version = "3.1.4"))
        jfull_dep = JSON.lower(full_dep)
        @test jfull_dep == Dict("type" => "dependency", "name" => "Baz_jll", "uuid" => "00000000-1111-2222-3333-444444444444", "compat" => "", "version-major" => 0x3, "version-minor" => 0x1, "version-patch" => 0x4, "platforms" => ["any"])
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
            @test "libz." * platform_dlext(platform) in readdir(last(libdirs(Prefix(destdir(dir, platform)))))
            @test "zlib.h" in readdir(joinpath(destdir(dir, platform), "include"))
            @test readdir(joinpath(destdir(dir, platform), "logs")) == ["Zlib.log.gz"]

            # Make sure the directories are emptied by `cleanup_dependencies`
            @test_nowarn cleanup_dependencies(prefix, ap, platform)
            @test readdir(joinpath(destdir(dir, platform), "include")) == []
            @test readdir(joinpath(destdir(dir, platform), "logs")) == []
        end

        # Setup a dependency of a JLL package which is also a standard library
        with_temp_project() do dir
            prefix = Prefix(dir)
            dependencies = [
                Dependency("LibCURL_jll")
            ]
            platform = HostPlatform()
            ap = @test_logs setup_dependencies(prefix, getpkg.(dependencies), platform)
            @test "libcurl." * platform_dlext(platform) in readdir(last(libdirs(Prefix(destdir(dir, platform)))))
            @test "curl.h" in readdir(joinpath(destdir(dir, platform), "include", "curl"))
            @test "libssh2." * platform_dlext(platform) in readdir(last(libdirs(Prefix(destdir(dir, platform)))))

            # Make sure the directories are emptied by `cleanup_dependencies`
            @test_nowarn cleanup_dependencies(prefix, ap, platform)
            # This shuld be empty, but the `curl/` directory is left here, empty
            @test_broken readdir(joinpath(destdir(dir, platform), "include")) == []
            @test readdir(joinpath(destdir(dir, platform), "logs")) == []
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
            @test "destdir" ∉ readdir(dirname(destdir(dir, platform)))
        end

        # Test setup of dependencies that depend on the Julia version
        with_temp_project() do dir
            prefix = Prefix(dir)
            dependencies = [Dependency("GMP_jll")]
            platform = Platform("x86_64", "linux"; julia_version=v"1.5")

            # Test that a particular version of GMP is installed
            ap = @test_logs setup_dependencies(prefix, getpkg.(dependencies), platform)
            @test isfile(joinpath(destdir(dir, platform), "lib", "libgmp.so.10.3.2"))
        end

        # Next, test on Julia v1.6
        with_temp_project() do dir
            prefix = Prefix(dir)
            dependencies = [Dependency("GMP_jll")]
            platform = Platform("x86_64", "linux"; julia_version=v"1.6")

            # Test that a particular version of GMP is installed
            ap = @test_logs setup_dependencies(prefix, getpkg.(dependencies), platform)
            @test isfile(joinpath(destdir(dir, platform), "lib", "libgmp.so.10.4.0"))
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
            @test isfile(joinpath(destdir(dir, platform), "lib", "libgmp.so.10.3.2"))
            @test isfile(joinpath(destdir(dir, platform), "lib", "libmpfr.so.6.1.0"))
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

using Test
using Pkg, Base.BinaryPlatforms
using BinaryBuilderBase
using BinaryBuilderBase: getname, getpkg, dependencify, dlext
using JSON

# Define equality between dependencies, in order to carry out the tests below
Base.:(==)(a::AbstractDependency, b::AbstractDependency) = getpkg(a) == getpkg(b)

if VERSION <= v"1.4"
    # Copy definition from Pkg v1.4, for compatibility
    function Base.:(==)(a::Pkg.Types.PackageSpec, b::Pkg.Types.PackageSpec)
        return a.name == b.name && a.uuid == b.uuid && a.version == b.version &&
            a.tree_hash == b.tree_hash && a.repo == b.repo && a.path == b.path &&
            a.pinned == b.pinned && a.mode == b.mode
    end
end

@testset "Dependencies" begin
    name = "Foo_jll"
    dep = Dependency(PackageSpec(; name = name))
    @test Dependency(name) == dep
    @test getname(dep) == name
    @test getname(PackageSpec(; name = name)) == name
    @test getpkg(dep) == PackageSpec(; name = name)
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
        mktempdir() do dir
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

        # Setup a dependency that doesn't have a mapping for the given platform
        mktempdir() do dir
            prefix = Prefix(dir)
            dependencies = [
                Dependency("LibOSXUnwind_jll")
            ]
            platform = Platform("i686", "linux"; libc="musl")
            @test_logs (:warn, r"Dependency LibOSXUnwind_jll does not have a mapping for artifact LibOSXUnwind for platform") begin
                setup_dependencies(prefix, getpkg.(dependencies), platform)
            end
            @test "destdir" ∉ readdir(joinpath(dir))
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

using Test
using Pkg
using BinaryBuilderBase

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

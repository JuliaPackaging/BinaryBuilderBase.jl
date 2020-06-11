using Test
using BinaryBuilderBase: extract_kwargs, extract_fields, strip_backslash, ArchiveSource

@testset "Compat functions" begin
    foo(; kwargs...) = collect(extract_kwargs(kwargs, (:bar, :qux)))
    @test foo(; a = 1) == Pair[]
    @test foo(; bar = 2, b = 3) == [:bar => 2]
    @test foo(; c = 4, qux = 5) == [:qux => 5]
    @test Set(foo(; qux = 6, d = 7, bar = 8)) == Set([:bar => 8, :qux => 6])

    @test extract_fields(ArchiveSource("http://example.org", "this is the hash"; unpack_target = "target")) == Dict("url" => "http://example.org", "hash" => "this is the hash", "unpack_target" => "target")

    @test strip_backslash("/home/wizard") == "/home/wizard"
    @test strip_backslash("/home/wizard/") == "/home/wizard"
    @test strip_backslash("/home//wizard///") == "/home//wizard"
    @test strip_backslash("wizard.jl") == "wizard.jl"
    # Test integration with `basename`
    @test basename(strip_backslash("/home/wizard")) == "wizard"
    @test basename(strip_backslash("/home/wizard/")) == "wizard"
    @test basename(strip_backslash("/home//wizard///")) == "wizard"
    @test basename(strip_backslash("wizard.jl")) == "wizard.jl"
end

using Test
using BinaryBuilderBase: strip_backslash

@testset "Compat functions" begin
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

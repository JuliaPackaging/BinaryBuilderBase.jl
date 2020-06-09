using Documenter, BinaryBuilderBase

makedocs(
    modules = [BinaryBuilderBase],
    sitename = "BinaryBuilderBase.jl",
)

deploydocs(
    repo = "github.com/JuliaPackaging/BinaryBuilderBase.jl.git",
    push_preview = true,
)

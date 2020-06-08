using Pkg
using BinaryBuilderBase
using BinaryBuilderBase: preferred_runner, exeext, dlext
using Pkg.PlatformEngines, Pkg.BinaryPlatforms
using Random, Libdl, Test, SHA

# The platform we're running on
const platform = platform_key_abi()

# Run all our tests
include("basic.jl")

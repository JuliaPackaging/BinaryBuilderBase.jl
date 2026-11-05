using Test, BinaryBuilderBase
using BinaryBuilderBase: iswasm, nbits, proc_family, prefer_clang, map_rust_target, cmake_os, meson_cpu_family,
                         select_compiler_versions, expand_cxxstring_abis, get_march_flags

# Needs a Julia whose Base.BinaryPlatforms knows wasm (JuliaLang/julia, "BinaryPlatforms: add wasm32/wasm64 ...")
@testset "WebAssembly" begin
    if !haskey(Base.BinaryPlatforms.arch_mapping, "wasm32")
        @test_skip "Base.BinaryPlatforms has no wasm"
    else
        p = Platform("wasm32", "wasi"; os_version = v"1")
        p64 = Platform("wasm64", "wasi")
        @test iswasm(p) && iswasm(p64) && !iswasm(Platform("x86_64", "linux"))
        @test triplet(p) == "wasm32-unknown-wasip1"
        @test nbits(p) == 32 && nbits(p64) == 64
        @test proc_family(p) == "wasm"
        @test prefer_clang(p)
        @test map_rust_target(p) == "wasm32-wasip1"
        @test cmake_os(p) == "WASI"
        @test meson_cpu_family(p) == "wasm32"
        @test get_march_flags("wasm32", nothing, "clang") == ["-mcpu=generic"]
        @test expand_cxxstring_abis(p) == [p]
        gccv, llvmv = select_compiler_versions(p, [:c])
        @test gccv === nothing && llvmv >= v"22"

        # compiler wrappers: clang with the wasm target and sysroot, no GCC flags, LLVM binutils
        mktempdir() do dir
            BinaryBuilderBase.generate_compiler_wrappers!(p; bin_path = dir, compilers = [:c], clang_use_lld = true)
            t = triplet(p)
            dir = joinpath(dir, t)
            clang = read(joinpath(dir, "$(t)-clang"), String)
            @test occursin("-target wasm32-unknown-wasip1", clang)
            @test occursin("--sysroot=/opt/wasm32-unknown-wasip1/wasm32-unknown-wasip1/sys-root", clang)
            @test !occursin("-rtlib=libgcc", clang)
            @test !occursin("_GLIBCXX_USE_CXX11_ABI", clang)
            @test !occursin("gcc-install-dir", clang)
            @test occursin("-stdlib=libc++", read(joinpath(dir, "$(t)-clang++"), String))
            @test occursin("-target wasm32-unknown-wasip1", read(joinpath(dir, "$(t)-cc"), String))
            @test occursin("/opt/x86_64-linux-musl/bin/llvm-ranlib", read(joinpath(dir, "$(t)-ranlib"), String))
            @test occursin("/opt/x86_64-linux-musl/bin/llvm-nm", read(joinpath(dir, "$(t)-nm"), String))
            @test occursin("/opt/x86_64-linux-musl/bin/llvm-ar", read(joinpath(dir, "$(t)-ar"), String))
            @test occursin("/opt/x86_64-linux-musl/bin/wasm-ld", read(joinpath(dir, "$(t)-ld"), String))
        end
    end
end

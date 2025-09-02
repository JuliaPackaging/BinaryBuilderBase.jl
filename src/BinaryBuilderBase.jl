module BinaryBuilderBase

using Pkg, Pkg.Artifacts, Random, Libdl, InteractiveUtils
using Base.BinaryPlatforms
using Downloads
using JSON, OutputCollectors, Scratch
import HistoricalStdlibVersions

# Re-export useful stuff from Base.BinaryPlatforms:
export HostPlatform, platform_dlext, valid_dl_path, arch, libc,
       libgfortran_version, libstdcxx_version, cxxstring_abi,
       detect_libgfortran_version, detect_libstdcxx_version, detect_cxxstring_abi,
       call_abi, wordsize, triplet, select_platform, platforms_match,
       Platform, AnyPlatform

export AbstractSource, AbstractDependency, SetupSource, PatchSource,
    resolve_jlls, coerce_dependency, coerce_source, Runner,
    generate_compiler_wrappers!, preferred_runner, CompilerShard, UserNSRunner,
    DockerRunner, choose_shards, exeext, preferred_libgfortran_version,
    preferred_cxxstring_abi, gcc_version, available_gcc_builds, getversion,
    getpkg, aatriplet, getcompat,
    nbits, proc_family, storage_dir, extract_kwargs, extract_fields,
    download_source, setup_workspace, setup_dependencies, update_registry,
    getname, cleanup_dependencies, compress_dir, prepare_for_deletion,
    run_interactive, sourcify, dependencify, with_logfile, get_concrete_platform,
    manage_shards

include("compat.jl")

include("riscv64.jl")

include("ArchiveUtils.jl")
include("Sources.jl")
include("Dependencies.jl")
include("Prefix.jl")
include("Products.jl")
include("Platforms.jl")

include("Runner.jl")
include("BuildToolchains.jl")
include("Rootfs.jl")
include("squashfs_utils.jl")
include("UserNSRunner.jl")
include("DockerRunner.jl")

include("utils.jl")

# This is the location that all binary builder-related files are stored under.
# downloads, unpacked .tar.gz shards, mounted shards, ccache cache, etc....
function storage_dir(args::AbstractString...)
    global storage_cache
    dir = joinpath(storage_cache[], args...)
    mkpath(dirname(dir))
    return dir
end
ccache_dir() = get(ENV, "BINARYBUILDER_CCACHE_DIR", storage_dir("ccache"))

"""
    enable_apple_file()

Return the path to file that, if exists, indicates that the user accepts to
download macOS SDK.  The file is automatically created when the package is
loaded if the environment variable `BINARYBUILDER_AUTOMATIC_APPLE` is set to
`"true"`.
"""
enable_apple_file() = storage_dir("enable_apple")

# These globals store important information such as where we're downloading
# the rootfs to, and where we're unpacking it.  These constants are initialized
# by `__init__()` to allow for environment variable overrides from the user.
const storage_cache = Ref("")
const use_squashfs = Ref(false)
const allow_ecryptfs = Ref(false)
const use_ccache = Ref(false)
const bootstrap_list = Symbol[]

function get_bbb_version(dir=@__DIR__, uuid="7f725544-6523-48cd-82d1-3fa08ff4056e")
    # Get BinaryBuilder.jl's version and git sha
    version = Pkg.TOML.parsefile(joinpath(dir, "..", "Project.toml"))["version"]
    try
        # get the gitsha if we can
        repo = LibGit2.GitRepo(dirname(@__DIR__))
        gitsha = string(LibGit2.GitHash(LibGit2.GitCommit(repo, "HEAD")))
        return VersionNumber("$(version)-git-$(gitsha[1:10])")
    catch
        try
            # Settle for the treehash otherwise
            env = Pkg.Types.Context().env
            bb_uuid = Pkg.Types.UUID(uuid)
            treehash = bytes2hex(env.manifest[bb_uuid].tree_hash.bytes)
            return VersionNumber("$(version)-tree-$(treehash[1:10])")
        catch
            # Something went so wrong, we can't get any of that.
            return VersionNumber(version)
        end
    end
end

"""
    versioninfo()

Helper function to print out some debugging information
"""
function versioninfo(; name=@__MODULE__, version=get_bbb_version())
    @info("Julia versioninfo(): ")
    InteractiveUtils.versioninfo()

    @info("$(name).jl version: $(version)")

    @static if Sys.isunix()
        @info("Kernel version: $(readchomp(`uname -r`))")
    end

    # Dump if some important directories are encrypted:
    @static if Sys.islinux()
        print_enc(n, path) = begin
            is_encrypted, mountpoint = is_ecryptfs(path)
            if is_encrypted
                @info("$n is encrypted on mountpoint $mountpoint")
            else
                @info("$n is NOT encrypted on mountpoint $mountpoint")
            end
        end

        print_enc("pkg dir", dirname(@__FILE__))
        print_enc("storage dir", storage_dir())
    end

    # Dump any relevant environment variables:
    @info("Relevant environment variables:")
    env_var_suffixes = [
        "AUTOMATIC_APPLE",
        "USE_SQUASHFS",
        "STORAGE_DIR",
        "RUNNER",
        "ALLOW_ECRYPTFS",
        "USE_CCACHE",
    ]
    for e in env_var_suffixes
        envvar = "BINARYBUILDER_$(e)"
        if haskey(ENV, envvar)
            @info("  $(envvar): \"$(ENV[envvar])\"")
        end
    end

    # Print out the preferred runner stuff here:
    @info("Preferred runner: $(preferred_runner())")

    # Try to run 'echo julia' in Linux x86_64 environment
    @info("Trying to run `echo hello julia` within a Linux x86_64 environment...")

    runner = preferred_runner()(
        pwd();
        cwd="/workspace/",
        platform=Platform("x86_64", "linux"),
        verbose=true
    )
    run_interactive(runner, `/bin/bash -c "echo hello julia"`)

    # If we use ccache, dump the ccache stats
    if use_ccache[]
        @info("ccache stats:")
        runner = preferred_runner()(
            pwd();
            cwd="/workspace/",
            platform=Platform("x86_64", "linux"),
        )
        run_interactive(runner, `/usr/bin/ccache -s`)
    end
    return nothing
end

function __init__()
    global runner_override, use_squashfs, allow_ecryptfs
    global use_ccache, storage_cache

    # Allow the user to override the default value for `storage_dir`
    storage_cache[] = get(ENV, "BINARYBUILDER_STORAGE_DIR",
                          @get_scratch!("storage_cache"))

    # If the user has signalled that they really want us to automatically
    # accept apple EULAs, do that.
    if get(ENV, "BINARYBUILDER_AUTOMATIC_APPLE", "") == "true"
        touch(enable_apple_file())
    end

    # If the user has overridden our runner selection algorithms, honor that
    runner_override[] = lowercase(get(ENV, "BINARYBUILDER_RUNNER", ""))
    if runner_override[] == "unprivileged"
        runner_override[] = "userns"
    end
    if !(runner_override[] in ("", "userns", "privileged", "docker"))
        @warn("Invalid runner value $(runner_override[]), ignoring...")
        runner_override[] = ""
    end

    # If the user has asked for squashfs mounting instead of tarball mounting,
    # use that here.  We default to using tarballs and not squashfs images as
    # using them requires `sudo` access.
    if get(ENV, "BINARYBUILDER_USE_SQUASHFS", "") == "false"
        use_squashfs[] = false
    elseif get(ENV, "BINARYBUILDER_USE_SQUASHFS", "") == "true"
        use_squashfs[] = true
    else
        # If it hasn't been specified but we're going to use the docker runner,
        # then set `use_squashfs` to `true` here.
        if preferred_runner() == DockerRunner
            # Conversely, if we're dock'ing it up, don't use it.
            use_squashfs[] = false
        elseif runner_override[] == "privileged"
            # If we're forcing a privileged runner, go ahead and default to squashfs
            use_squashfs[] = true
        end
    end

    # If the user has signified that they want to allow mounting of ecryptfs
    # paths, then let them do so at their own peril.
    if get(ENV, "BINARYBUILDER_ALLOW_ECRYPTFS", "") == "true"
        allow_ecryptfs[] = true
    end

    # If the user has enabled `ccache` support, use it!
    if get(ENV, "BINARYBUILDER_USE_CCACHE", "false") == "true"
        use_ccache[] = true
    end

    # Populate `Pkg.Types.STDLIBS_BY_VERSION`.
    HistoricalStdlibVersions.register!()
end


end # module BinaryBuilderBase

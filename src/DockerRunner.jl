"""
    DockerRunner

Use `docker` as an execution engine; a reasonable backup for platforms that do
not have user namespaces (e.g. MacOS, Windows).
"""
mutable struct DockerRunner <: Runner
    docker_cmd::Cmd
    env::Dict{String, String}
    platform::AbstractPlatform

    shards::Vector{CompilerShard}
    workspace_root::String
end

docker_image(version::VersionNumber) = "julia_binarybuilder_rootfs:v$(version)"
function docker_image(rootfs::CompilerShard)
    name = artifact_name(rootfs)
    hash = artifact_hash(name, artifacts_toml; platform=rootfs.host)
    return string(
        "julia_binarybuilder_rootfs:",
        "v",
        string(rootfs.version),
        "-",
        string(bytes2hex(hash.bytes))[end-5:end],
    )
end

"""
    import_docker_image(rootfs::CompilerShard; verbose::Bool = false)

Checks to see if the given rootfs has been imported into docker yet; if it
hasn't, then do so so that we can run things like:

    docker run -ti binarybuilder_rootfs:v2018.08.27 /bin/bash

Which, after all, is the foundation upon which this whole doodad is built.
"""
function import_docker_image(rootfs::CompilerShard, workspace_root::String; verbose::Bool = false)
    # Does this image already exist?  If so, we're done!
    if success(`docker inspect --type=image $(docker_image(rootfs))`)
        if verbose
            @info("Docker base image already exists, skipping import...")
        end
        return
    end

    # Otherwise, import it!
    dockerfile_cmds = "ENTRYPOINT [\"/docker_entrypoint.sh\"]"
    rootfs_path = mount(rootfs, workspace_root; verbose=verbose)
    if verbose
        @info("Importing docker base image from $(rootfs_path) to $(docker_image(rootfs))")
    end
    try
        run(pipeline(pipeline(
            `tar -c -C $(rootfs_path) .`,
            `docker import - -c $(dockerfile_cmds) $(docker_image(rootfs))`;
        ); stdout=devnull))
    finally
        unmount(rootfs, workspace_root)
    end
    return
end

# Helper function to delete a previously-imported docker image
delete_docker_image() = delete_docker_image(first(choose_shards(HostPlatform())))
delete_docker_image(rootfs::CompilerShard) = success(`docker rmi -f $(docker_image(rootfs))`)

function DockerRunner(workspace_root::String;
                      cwd = nothing,
                      platform::AbstractPlatform = HostPlatform(),
                      workspaces::Vector = [],
                      extra_env=Dict{String, String}(),
                      verbose::Bool = false,
                      compiler_wrapper_path::String = mktempdir(),
                      toolchains_path::String = mktempdir(),
                      src_name::AbstractString = "",
                      shards = nothing,
                      kwargs...)
    global use_ccache

    platform, envs, shards =
        runner_setup!(workspaces, workspaces, workspace_root, verbose, kwargs,
                      platform, src_name, extra_env, compiler_wrapper_path,
                      toolchains_path, shards)

    # Import docker image
    import_docker_image(shards[1], workspace_root; verbose=verbose)

    # Construct docker command
    docker_cmd = `docker run --rm --privileged `#--cap-add SYS_ADMIN`

    if cwd !== nothing
        docker_cmd = `$docker_cmd -w /$(abspath(cwd))`
    end

    # Add in read-only mappings and read-write workspaces
    for shard in shards[2:end]
        outside = mount_path(shard, workspace_root)
        inside = map_target(shard)
        docker_cmd = `$docker_cmd -v $(outside):$(inside):ro`
    end
    for (outside, inside) in workspaces
        if isdir(outside) || isfile(outside)
            outside = realpath(outside)
        end
        docker_cmd = `$docker_cmd -v $(outside):$inside`
    end

    # Build up environment mappings
    for (k, v) in envs
        docker_cmd = `$docker_cmd -e $k=$v`
    end

    # Finally, return the DockerRunner in all its glory
    return DockerRunner(docker_cmd, envs, platform, shards, workspace_root)
end

"""
    chown_cleanup(dr::DockerRunner)

On Linux, the user id inside of the docker container doesn't correspond to ours
on the outside, so permissions get all kinds of screwed up.  To fix this, we
have to `chown -R \$(id -u):\$(id -g) \$prefix`, which really sucks, but is
still better than nothing.  This is why we prefer the UserNSRunner on Linux.
"""
function chown_cleanup(dr::DockerRunner; verbose::Bool = false)
    if !Sys.islinux()
        return
    end

    if verbose
        @info("chown'ing prefix back to us...")
    end
    run(`$(sudo_cmd()) chown $(getuid()):$(getgid()) -R $(dr.workspace_root)`)
end

function Base.run(dr::DockerRunner, cmd, logger::IO=stdout; verbose::Bool=false, tee_stream=stdout)
    did_succeed = true
    docker_cmd = `$(dr.docker_cmd) $(docker_image(dr.shards[1])) $(cmd)`
    @debug("About to run: $(docker_cmd)")

    try
        mount_shards(dr; verbose=verbose)
        oc = OutputCollector(docker_cmd; verbose=verbose, tee_stream=tee_stream)
        did_succeed = wait(oc)

        # First write out the actual command, then the command output
        println(logger, cmd)
        print(logger, merge(oc))
    finally
        unmount_shards(dr; verbose=verbose)

        # Cleanup permissions, if we need to.
        chown_cleanup(dr; verbose=verbose)
    end

    # Return whether we succeeded or not
    return did_succeed
end

function Base.read(dr::DockerRunner, cmd; verbose=false)
    did_succeed = true
    docker_cmd = `$(dr.docker_cmd) $(docker_image(dr.shards[1])) $(cmd)`
    @debug("About to run: $(docker_cmd)")

    local oc
    did_succeed = false
    try
        mount_shards(dr; verbose=verbose)
        oc = OutputCollector(docker_cmd; verbose=verbose)
        did_succeed = wait(oc)
    finally
        unmount_shards(dr; verbose=verbose)

        # Cleanup permissions, if we need to.
        chown_cleanup(dr; verbose=verbose)
    end

    if !did_succeed
        print(stderr, collect_stderr(oc))
        return nothing
    end

    return collect_stdout(oc)
end

function run_interactive(dr::DockerRunner, cmd::Cmd; stdin = nothing, stdout = nothing, stderr = nothing, verbose::Bool = false)
    function tty_or_nothing((s, bs))
        # If the `s` stream is `nothing`, we need to check whether the
        # corresponding Base stream `bs` is a TTY.
        s === nothing && (s = bs)
        return typeof(s) <: Base.TTY
    end
    run_flags = all(tty_or_nothing.(((stdin, Base.stdin), (stdout, Base.stdout), (stderr, Base.stderr)))) ? "-ti" : "-i"
    docker_cmd = `$(dr.docker_cmd) $(run_flags) -i $(docker_image(dr.shards[1])) $(cmd.exec)`
    if cmd.ignorestatus
        docker_cmd = ignorestatus(docker_cmd)
    end
    @debug("About to run: $(docker_cmd)")

    if stdin isa AnyRedirectable
        docker_cmd = pipeline(docker_cmd, stdin=stdin)
    end
    if stdout isa AnyRedirectable
        docker_cmd = pipeline(docker_cmd, stdout=stdout)
    end
    if stderr isa AnyRedirectable
        docker_cmd = pipeline(docker_cmd, stderr=stderr)
    end

    try
        mount_shards(dr; verbose=verbose)
        return success(run(docker_cmd))
    finally
        unmount_shards(dr; verbose=verbose)
        # Cleanup permissions, if we need to.
        chown_cleanup(dr; verbose=verbose)
    end
end

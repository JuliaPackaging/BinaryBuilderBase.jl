# Utilities to rewrite UIDs in .squashfs files.

"""
    getuid()

Wrapper around libc's `getuid()` function
"""
function getuid()
    return ccall(:getuid, Cint, ())
end

"""
    getgid()

Wrapper around libc's `getgid()` function
"""
function getgid()
    return ccall(:getgid, Cint, ())
end


# Note: produce these values by #including squashfs_fs.h from linux in Cxx.jl
# and running the indicated command
const offsetof_id_table_start = 0x30    # offsetof(struct suqashfs_super_block, id_table_start)
const offsetof_no_ids = 0x1a            # offsetof(struct suqashfs_super_block, no_ids)

# From squashfs_fs.h
const SQUASHFS_COMPRESSED_BIT = UInt16(1) << 15
const SQUASHFS_MAGIC = 0x73717368

"""
    generate_per_uid_squashfs(cs, new_uid = getuid())

In order for the sandbox to work well, we need to have the uids of the squashfs
images match the uid of the current unprivileged user.  Unfortunately there is
no mount-time option to do this for us.  Fortunately, squashfs is simple enough
that if the ID table is uncompressed, we can just manually patch the uids to be
what we need.  This function performs this operation, by rewriting all UIDs and
GIDs to the given `new_uid` (which defaults to the current user's UID).
"""
function generate_per_uid_squashfs(cs, new_uid = getuid(); verbose::Bool = false)
    # Because the source .squashfs file comes as an immutable artifact, we will create
    # a copy that is based off of the .squashfs artifact, but with rewritten UIDs
    cache_path = shard_path(cs)

    # Regenerate the cache if it doesn't exist.
    if !isfile(cache_path)
        # Grab the progenitor path, downloading it if necessary
        progenitor_path = joinpath(artifact_path(progenitor_hash), name)

        if !isfile(progenitor_path)
            error("Compiler shard $(name) missing from disk at $(progenitor_path)")
        end

        # Copy .squashfs file over to our local directory, make it writable
        cp(progenitor_path, cache_path)
        chmod(cache_path, 0o644)

        open(cache_path, "r+") do file
            # Check magic
            if read(file, UInt32) != SQUASHFS_MAGIC
                error("`$progenitor_path` is not a squashfs file")
            end
            # Check that the image contains only one id (which we will rewrite)
            seek(file, offsetof_no_ids)
            if read(file, UInt16) != 1
                error("`$progenitor_path` uses more than one uid/gid")
            end
            # Find the index table
            seek(file, offsetof_id_table_start)
            offset = read(file, UInt64)
            seek(file, offset)
            # Find the correct metdata block
            index = read(file, UInt64)
            seek(file, index)
            # Read the metadata block
            size = read(file, UInt16)
            # Make sure it's uncompressed (yes, I know that flag is terribly
            # named - it indicates that the data is uncompressed)
            if ((size & SQUASHFS_COMPRESSED_BIT) == 0)
                error("Metadata block is compressed")
            end
            p = position(file)
            uid = read(file, UInt32)
            if uid == new_uid
                return
            end
            if verbose
                @info("Rewriting $(basename(progenitor_path)) from UID $(uid) -> $(new_uid)")
            end
            seek(file, p)
            write(file, UInt32(new_uid))
        end
    end

    # Finally, return the path to that cached squashfs file
    return cache_path
end


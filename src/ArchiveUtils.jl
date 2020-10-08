using Downloads, Tar, p7zip_jll, SimpleBufferStream, SHA

export unpack, list_tarball_files, verify, download_verify

function detect_compressor(header::Vector)
    compressor_magic_bytes = Dict(
        "gzip" => [0x1f, 0x8b],
        "xz" => [0xfd, 0x37, 0x7a, 0x58, 0x5A, 0x00],
        "zstd" => [0x28, 0xB5, 0x2F, 0xFD],
        "bzip2" => [0x42, 0x5a, 0x68],
    )
    for (compressor, magic) in compressor_magic_bytes
        lm = length(magic)
        if length(header) >= lm && header[1:lm] == magic
            return compressor
        end
    end
    return nothing
end

function decompress(path::AbstractString)
    # Read the first few bytes of data to classify it:
    compressor = open(path) do io
        detect_compressor(read(io, 6))
    end
    if compressor === nothing
        error("Called decompress() on uncompressed file")
    end

    p7zip() do p7z
        # Launch p7zip as our decompressor engine, clueing it in to the compressor
        p = open(`$p7z e $(path) -so -t$(compressor)`; read=true)
        return p.out
    end
end

# Many functions don't like `PipeEndpoint`, so we interface with a BufferStream
function buff_wrap(io::IO; blocksize = 2*1024*1024)
    buff = BufferStream(blocksize)
    @async begin
        while !eof(io)
            write(buff, readavailable(io))
        end
        close(buff)
    end
    return buff
end


# Reimplement Pkg.PlatformEngines verbs using Tar and Downloader
function unpack(tarball_path::AbstractString, dest::AbstractString)
    mkpath(dest)

    @sync begin
        Tar.extract(decompress(tarball_path), dest)
    end
end

function list_tarball_files(tarball_path::AbstractString)
    @sync begin
        # Decompress to a file, since `Tar.list()` can't feed off of a BufferStream yet
        mktemp() do path, _
            function remove_dotslash(path)
                if startswith(path, "./")
                    return string(path[3:end])
                end
                return path
            end
            return String[remove_dotslash(h.path) for h in Tar.list(buff_wrap(decompress(tarball_path)))]
        end
    end
end

function verify(path::AbstractString, hash::AbstractString; hash_path::AbstractString="$(path).sha256")
    # Check hash string format
    if !occursin(r"^[0-9a-f]{64}$"i, hash)
        msg = "Hash value must be 64 hexadecimal characters (256 bits), "
        if !isascii(hash)
            msg *= "given hash value is non-ASCII"
        elseif occursin(r"^[0-9a-f]*$"i, hash)
            msg *= "given hash value has the wrong length ($(length(hash)))"
        else
            msg *= "given hash value contains non-hexadecimal characters"
        end
        msg *= ": $(repr(hash))"
        error(msg)
    end
    hash = lowercase(hash)


    # First, it must exist
    if isfile(hash_path)
        # Next, it must contain the same hash as what we're verifying against
        if read(hash_path, String) == hash
            # Next, it must be no older than the actual path
            if stat(hash_path).mtime >= stat(path).mtime
                return true
            end
        end
    end

    calc_hash = open(path) do file
        bytes2hex(sha256(file))
    end
    @assert occursin(r"^[0-9a-f]{64}$", calc_hash)

    if calc_hash != hash
        msg  = "Hash Mismatch!\n"
        msg *= "  Expected sha256:   $hash\n"
        msg *= "  Calculated sha256: $calc_hash"
        @error(msg)
        return false
    end

    # Try to save a hash cache if everything worked out fine
    try
        open(hash_path, "w") do file
            write(file, hash)
        end
    catch e
        if isa(e, InterruptException)
            rethrow(e)
        end
    end

    return true
end

function download_verify(url, hash, path)
    Downloads.download(url, path)

    if !isfile(path)
        # Hopefully it shouldn't happen, but better check
        error("Destination file $(path) not created")
    end

    if !verify(path, hash)
        # When we are on Yggdrasil, upload the failed download to S3, to see what went wrong
        if get(ENV, "YGGDRASIL", "false") == "true"
            CALC_HASH = open(path) do file
                bytes2hex(sha256(file))
            end
            ACL="x-amz-acl:public-read"
            CONTENT_TYPE="application/x-gtar"
            BUCKET="julia-bb-buildcache"
            BUCKET_PATH="$(ENV["BB_HASH"])/$(CALC_HASH)/$(basename(path))"
            DATE=readchomp(`date -R`)
            S3SIGNATURE=readchomp(pipeline(`echo -en "PUT\n\n$(CONTENT_TYPE)\n$(DATE)\n$(ACL)\n/$(BUCKET)/$(BUCKET_PATH)"`,
                                           `openssl sha1 -hmac "$(ENV["S3SECRET"])" -binary`,
                                           `base64`))
            HOST="$(BUCKET).s3.amazonaws.com"
            @info "Download of $(url) failed"
            @info "Computed SHA256 hash: $(CALC_HASH)"
            @info "Uploading downloaded file to https://$(HOST)/$(BUCKET_PATH)"
            run(`curl -X PUT -T "$(path)"
                    -H "Host: $(HOST)"
                    -H "Date: $(DATE)"
                    -H "Content-Type: $(CONTENT_TYPE)"
                    -H "$(ACL)"
                    -H "Authorization: AWS $(ENV["S3KEY"]):$(S3SIGNATURE)"
                    "https://$(HOST)/$(BUCKET_PATH)"`)
        end
        error("Verification failed")
    end

    return true
end

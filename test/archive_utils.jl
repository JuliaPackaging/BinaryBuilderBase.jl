using BinaryBuilderBase: Prefix, archive_artifact, package, list_tarball_files, detect_compressor
using Pkg.Artifacts: create_artifact, remove_artifact, with_artifacts_directory
using SHA
using Test

@testset "Archive Utils" begin
    @testset "package" begin
        mktempdir() do prefix
            # Create random files
            mkpath(joinpath(prefix, "bin"))
            mkpath(joinpath(prefix, "lib"))
            mkpath(joinpath(prefix, "etc"))
            bar_path = joinpath(prefix, "bin", "bar.sh")
            open(bar_path, "w") do f
                write(f, "#!/bin/sh\n")
                write(f, "echo yolo\n")
            end
            baz_path = joinpath(prefix, "lib", "baz.so")
            open(baz_path, "w") do f
                write(f, "this is not an actual .so\n")
            end

            qux_path = joinpath(prefix, "etc", "qux.conf")
            open(qux_path, "w") do f
                write(f, "use_julia=true\n")
            end

            mktempdir() do output_dir
                for (format, ext, hash) in (("gzip", "gz", "568f743e965b63d3187b6a2647700a71d1d7520b4596fbf2bfb39ffa67c4bb55"),
                                            ("xz", "xz", "293736704ee772836edf67ba4bac55c9604721d6df332cef9bdf4c9c06b39a8c"))
                    tarball_path =  joinpath(output_dir, "foo.tar.$ext")
                    package(prefix, tarball_path; format=format)
                    @test isfile(tarball_path)

                    compressor = open(tarball_path) do io
                        detect_compressor(read(io, 6))
                    end
                    # Make sure the compression format is what we expect
                    @test compressor == format

                    if !isempty(hash)
                        tarball_hash = open(tarball_path, "r") do io
                            bytes2hex(sha256(io))
                        end
                        @test tarball_hash == hash
                    end

                    # Test that we can inspect the contents of the tarball
                    contents = list_tarball_files(tarball_path)
                    @test "bin/bar.sh" in contents
                    @test "lib/baz.so" in contents
                    @test "etc/qux.conf" in contents
                end
            end
        end

        @testset "Filtering" begin
            lib = "libfoo"
            mktempdir() do src_dir
                # Create the files lib/libfoo.so and logs/libfoo.gz
                libname = joinpath("lib", lib * ".so")
                logname = joinpath("logs", lib * ".gz")
                mkpath(dirname(joinpath(src_dir, libname)))
                mkpath(dirname(joinpath(src_dir, logname)))
                touch(joinpath(src_dir, libname))
                touch(joinpath(src_dir, logname))

                # Create an artifact containing the full source directory
                mktempdir() do output_dir
                    tarball, tarball_hash, tree_hash = package(Prefix(src_dir), joinpath(output_dir, lib), v"1.2.3")
                    @test tarball_hash == "46abbba8bf97315ecf3d979fb1c95e2e1a639ab71d8d569736e68e6a2ab4a427"
                    @test tree_hash == Base.SHA1("b316cc5e582cbd503b2da34bd1b79aaf3941ad80")
                    contents = list_tarball_files(tarball)
                    @test libname ∈ contents
                    @test logname ∈ contents
                end

                # Create an artifact containing *only* the log file logs/libfoo.gz
                mktempdir() do output_dir
                    tarball, tarball_hash, tree_hash = package(Prefix(src_dir), joinpath(output_dir, lib), v"1.2.3"; filter=(_, f) -> f == "logs")
                    @test tarball_hash == "6b51bcbed720e98d5eaef43a0b10d5b08e11ff05d05fe3ca9525686871767c4c"
                    @test tree_hash == Base.SHA1("3a3ccf24312676bdd8c2ec769232dbd3bd1b9857")
                    contents = list_tarball_files(tarball)
                    @test libname ∉ contents
                    @test logname ∈ contents
                end
            end
        end

    end

    @testset "Artifact archival" begin
        mktempdir() do art_dir
            with_artifacts_directory(art_dir) do
                hash = create_artifact(p -> touch(joinpath(p, "foo")))
                tarball_path = joinpath(art_dir, "foo.tar.gz")
                @test archive_artifact(hash, tarball_path) == "59f35d4bde88850c3e80d6890770902ca6e9e6c3a3b3e9343df686a7b28e89b0"
                @test "foo" in list_tarball_files(tarball_path)
                rm(tarball_path)

                # Test custom `package` function and ensure failure if no `tarball_path` file
                # is created.
                package_alt(src_dir, tarball_path; format=nothing) = nothing
                @test !isfile(tarball_path)
                @test_throws SystemError archive_artifact(hash, tarball_path, package=package_alt)

                # Test archiving something that doesn't exist fails
                remove_artifact(hash)
                @test_throws ErrorException archive_artifact(hash, tarball_path)
            end
        end
    end
end

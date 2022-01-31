using BinaryBuilderBase: archive_artifact, package, list_tarball_files
using Pkg.Artifacts: create_artifact, remove_artifact, with_artifacts_directory

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
                for (format, ext) in [("gzip", "gz"), ("xz", "xz")]
                    tarball_path =  joinpath(output_dir, "foo.tar.$ext")
                    package(prefix, tarball_path; format=format)
                    @test isfile(tarball_path)

                    # Test that we can inspect the contents of the tarball
                    contents = list_tarball_files(tarball_path)
                    @test "bin/bar.sh" in contents
                    @test "lib/baz.so" in contents
                    @test "etc/qux.conf" in contents
                end
            end
        end
    end

    @testset "Artifact archival" begin
        mktempdir() do art_dir
            with_artifacts_directory(art_dir) do
                hash = create_artifact(p -> touch(joinpath(p, "foo")))
                tarball_path = joinpath(art_dir, "foo.tar.gz")
                archive_artifact(hash, tarball_path)
                @test "foo" in list_tarball_files(tarball_path)
                rm(tarball_path)

                # Test custom `package` function and ensure failure if no `tarball_path` file
                # is created.
                package_alt(src_dir, tarball_path) = nothing
                @test !isfile(tarball_path)
                @test_throws SystemError archive_artifact(hash, tarball_path, package=package_alt)

                # Test archiving something that doesn't exist fails
                remove_artifact(hash)
                @test_throws ErrorException archive_artifact(hash, tarball_path)
            end
        end
    end
end

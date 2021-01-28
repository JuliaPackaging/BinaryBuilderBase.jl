using UUIDs

export Dependency, BuildDependency, HostBuildDependency,
    is_host_dependency, is_target_dependency, is_build_dependency, is_runtime_dependency


# Pkg.PackageSpec return different types in different Julia versions so...
const PkgSpec = typeof(Pkg.PackageSpec(name="dummy"))

"""
An `AbstractDependency` is a binary dependency of the JLL package.  Dependencies
are installed to `\${prefix}` in the build environment.

Concrete subtypes of `AbstractDependency` are

* [`Dependency`](@ref): a JLL package that is necessary for to build the package
  and to load the generated JLL package.
* [`BuildDependency`](@ref): a JLL package that is necessary only to build the
  package.  This will not be a dependency of the generated JLL package.
* [`HostBuildDependency`](@ref): similar to `BuildDependency`, but it will
  install the artifact for the host platform, instead of that for the target
  platform.
"""
abstract type AbstractDependency end

"""
    is_host_dependency(dep::AbstractDependency) -> Bool

Return whether `dep` is a dependency of the host platform or not.
"""
is_host_dependency

"""
    is_target_dependency(dep::AbstractDependency) -> Bool

Return whether `dep` is a dependency of the target platform or not.
"""
is_target_dependency(dep::AbstractDependency) = !is_host_dependency(dep)

"""
    is_build_dependency(dep::AbstractDependency) -> Bool

Return whether `dep` is a build-time dependency or not.
"""
is_build_dependency

"""
    is_runtime_dependency(dep::AbstractDependency) -> Bool

Return whether `dep` is a runtime dependency or not.
"""
is_runtime_dependency

"""
    Dependency(dep::Union{PackageSpec,String})

Define a binary dependency that is necessary to build the package and load the
generated JLL package.  The argument can be either a string with the name of the
JLL package or a `Pkg.PackageSpec`.
"""
struct Dependency <: AbstractDependency
    pkg::PkgSpec
    build_version::Union{VersionNumber,Nothing}
    Dependency(pkg::PkgSpec, build_version = nothing) = new(pkg, build_version)
end
Dependency(dep::AbstractString, build_version = nothing) = Dependency(PackageSpec(; name = dep), build_version)
is_host_dependency(::Dependency) = false
is_build_dependency(::Dependency) = true
is_runtime_dependency(::Dependency) = true

"""
    BuildDependency(dep::Union{PackageSpec,String})

Define a binary dependency that is necessary only to build the package.  The
argument can be either a string with the name of the JLL package or a
`Pkg.PackageSpec`.
"""
struct BuildDependency <: AbstractDependency
    pkg::PkgSpec
end
BuildDependency(dep::AbstractString) = BuildDependency(PackageSpec(; name = dep))
is_host_dependency(::BuildDependency) = false
is_build_dependency(::BuildDependency) = true
is_runtime_dependency(::BuildDependency) = false

"""
    HostBuildDependency(dep::Union{PackageSpec,String})

Define a binary dependency that is necessary only to build the package.
Different from the [`BuildDependency`](@ref), the artifact for the host
platform will be installed, instead of that for the target platform.

The argument can be either a string with the name of the JLL package or a
`Pkg.PackageSpec`.
"""
struct HostBuildDependency <: AbstractDependency
    pkg::PkgSpec
end
HostBuildDependency(dep::AbstractString) = HostBuildDependency(PackageSpec(; name = dep))
is_host_dependency(::HostBuildDependency) = true
is_build_dependency(::HostBuildDependency) = true
is_runtime_dependency(::HostBuildDependency) = false

getpkg(d::AbstractDependency) = d.pkg
function getpkg(d::Dependency)
    # A Dependency can have a separate build_version, so replace that here:
    pkg = d.pkg
    if d.build_version !== nothing
        pkg = deepcopy(pkg)
        pkg.version = Pkg.Types.VersionSpec(d.build_version)
    end
    return pkg
end

getname(x::PkgSpec) = x.name
getname(x::AbstractDependency) = getname(getpkg(x))

# Wrapper around `Pkg.Types.registry_resolve!` which keeps the type of the
# dependencies.  TODO: improve this
function registry_resolve!(ctx, dependencies::Vector{<:AbstractDependency})
    resolved_dependencies = Pkg.Types.registry_resolve!(ctx, getpkg.(dependencies))
    for idx in eachindex(dependencies)
        dependencies[idx] = typeof(dependencies[idx])(resolved_dependencies[idx])
    end
    return dependencies
end

# We only want to update the registry once per run
registry_updated = false
function update_registry(ctx = Pkg.Types.Context(), outs = stdout)
    global registry_updated
    if !registry_updated
        Pkg.Registry.update(ctx,
            [Pkg.Types.RegistrySpec(uuid = "23338594-aafe-5451-b93e-139f81909106")];
            io=outs,
        )
        registry_updated = true
    end
end

function resolve_jlls(dependencies::Vector; ctx = Pkg.Types.Context(), outs=stdout)
    if isempty(dependencies)
        return true, Dependency[]
    end

    # Don't clobber caller
    # XXX: Coercion is needed as long as we support old-style dependencies.
    dependencies = deepcopy(coerce_dependency.(dependencies))

    # If all dependencies already have a UUID, return early
    if all(x->getpkg(x).uuid !== nothing, dependencies)
        return true, dependencies
    end

    # Resolve, returning the newly-resolved dependencies
    update_registry(ctx, outs)
    dependencies = registry_resolve!(ctx, dependencies)

    # But first, check to see if anything failed to resolve, and warn about it:
    all_resolved = true
    for dep in getpkg.(dependencies)
        if dep.uuid === nothing
            @warn("Unable to resolve $(getname(dep))")
            all_resolved = false
        end
    end
    return all_resolved, dependencies
end

# Add JSON serialization of dependencies
string_or_nothing(x) = isnothing(x) ? x : string(x)

major(v::VersionNumber) = v.major
minor(v::VersionNumber) = v.minor
patch(v::VersionNumber) = v.patch
major(v::Pkg.Types.VersionBound) = v.t[1]
minor(v::Pkg.Types.VersionBound) = v.t[2]
patch(v::Pkg.Types.VersionBound) = v.t[3]
__version(v::VersionNumber) = v
__version(v::Pkg.Types.VersionSpec) = v.ranges[1].lower
version(d::AbstractDependency) = __version(getpkg(d).version)
version(d::Dependency) = __version(d.pkg.version)

for (type, type_descr) in ((Dependency, "dependency"), (BuildDependency, "builddependency"), (HostBuildDependency, "hostdependency"))
    JSON.lower(d::type) = Dict("type" => type_descr,
                               "name" => d.pkg.name,
                               "uuid" => string_or_nothing(d.pkg.uuid),
                               "version-major" => major(version(d)),
                               "version-minor" => minor(version(d)),
                               "version-patch" => patch(version(d)))
end

# When deserialiasing the JSON file, the dependencies are in the form of
# dictionaries.  This function converts the dictionary back to the appropriate
# AbstractDependency.
function dependencify(d::Dict)
    if d["type"] in ("dependency", "builddependency", "hostdependency")
        uuid = isnothing(d["uuid"]) ? d["uuid"] : UUID(d["uuid"])
        version = VersionNumber(d["version-major"], d["version-minor"], d["version-patch"])
        version = version == v"0" ? nothing : version
        T = if d["type"] == "dependency"
            Dependency
        elseif d["type"] == "builddependency"
            BuildDependency
        elseif d["type"] == "hostdependency"
            HostBuildDependency
        end
        return T(PackageSpec(; name = d["name"], uuid = uuid, version = version))
    else
        error("Cannot convert to dependency")
    end
end


# XXX: compatibility functions.  These are needed until we support old-style
# dependencies.
coerce_dependency(dep::AbstractDependency) = dep
function coerce_dependency(dep)
    @warn "Using PackageSpec or string as dependency is deprecated, use Dependency instead"
    Dependency(dep)
end

using UUIDs

export Dependency, BuildDependency

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
"""
abstract type AbstractDependency end

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

# helper to get the version of a dependency (and no the build_version)
version(d::AbstractDependency) = getpkg(d).version
version(d::Dependency) = d.pkg.version

for (type, type_descr) in ((Dependency, "dependency"), (BuildDependency, "builddependency"))
    JSON.lower(d::type) = Dict("type" => type_descr,
                               "name" => d.pkg.name,
                               "uuid" => string_or_nothing(d.pkg.uuid),
                               "version" => JSON.parse(JSON.json(version(d))))
end

import Pkg.Types: VersionBound, VersionRange, VersionSpec
dejson(::Type{VersionBound}, d::Dict{String,Any}) = VersionBound(NTuple{d["n"],Int}(d["t"]))
dejson(::Type{VersionRange}, d::Dict{String,Any}) = VersionRange(dejson(VersionBound, d["lower"]), dejson(VersionBound, d["upper"]))
dejson(::Type{VersionSpec}, d::Dict{String,Any}) = VersionSpec([dejson(VersionRange, v) for v in d["ranges"]])

# When deserialiasing the JSON file, the dependencies are in the form of
# dictionaries.  This function converts the dictionary back to the appropriate
# AbstractDependency.
function dependencify(d::Dict)
    if haskey(d, "uuid") && haskey(d, "version") && haskey(d, "name")
        uuid = isnothing(d["uuid"]) ? d["uuid"] : UUID(d["uuid"])
        version = dejson(VersionSpec, d["version"])
        pkg = PackageSpec(; name = d["name"], uuid = uuid, version = version)
        if d["type"] == "dependency"
            return Dependency(pkg)
        elseif d["type"] == "builddependency"
            return BuildDependency(pkg)
        end
    end
    error("Cannot convert to dependency")
end


# XXX: compatibility functions.  These are needed until we support old-style
# dependencies.
coerce_dependency(dep::AbstractDependency) = dep
function coerce_dependency(dep)
    @warn "Using PackageSpec or string as dependency is deprecated, use Dependency instead"
    Dependency(dep)
end

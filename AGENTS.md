# Agent Notes

## Artifact Tree Hashes

When updating `Artifacts.toml`, `git-tree-sha1` must be the hash of the extracted artifact tree, not the default raw tar stream hash.

Do not validate artifact tree hashes only with default `Tar.tree_hash` on a decompressed tar stream or with `Pkg.PlatformEngines.verify_archive_tree_hash`; those use the tar stream with `skip_empty=false` and can disagree with the hash Pkg computes after extraction when archives contain empty directories.

Use either of these checks instead:

```julia
using Tar
Tar.tree_hash(`gzip -dc $file`; skip_empty=true)
```

```julia
using Pkg, Tar
import Pkg.GitTools
mktempdir() do dir
    Tar.extract(`gzip -dc $file`, dir)
    bytes2hex(GitTools.tree_hash(dir))
end
```

The two values above should agree. Use that value for `git-tree-sha1`.

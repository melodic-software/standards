# Claude review smoke test (temporary)

Temporary file to validate that the `claude-review` caller runs on a real PR
after the caller workflow landed on `main`. This PR is **not** intended to merge.

Example snippet under review:

```bash
# Copy a build artifact to a release directory.
copy_artifact() {
  src=$1
  dest=$2
  cp $src $dest
}
```

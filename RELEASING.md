# Releasing

Steps to publish a new `ccc` release.

## 1. Ensure tests pass (local)

```bash
./test_impl.sh python
./test_impl.sh rust
```

Optional broader local sweep:

```bash
./run_all_tests.sh
```

## 2. Bump version

Update all four locations:

- `VERSION` — root version file
- `rust/Cargo.toml` — `version` field
- `rust/README.md` — `ccc = "x.y.z"` in the install example
- `rust/Cargo.lock` — run `cargo check` in `rust/` to regenerate

## 3. Update changelog

- `CHANGELOG.md` — move `## Unreleased` items (if any) into a new dated `## x.y.z - YYYY-MM-DD` section
- `SHARED_CHANGES.md` — add a dated entry for any shared semantic change

## 4. Commit and push

```bash
git add -A
git commit -m "Bump to x.y.z"
git push
```

## 5. Publish Rust crate

```bash
cd rust && cargo publish
```

## 6. Install locally

```bash
just install-rs
```

## 7. Tag (automatic GitHub Release + binaries)

Pushing a version tag triggers [`.github/workflows/release.yml`](.github/workflows/release.yml):

1. **Test gate** — must pass before anything is published:
   - `VERSION` / `rust/Cargo.toml` must match the tag
   - `./test_impl.sh` for Python, Rust, TypeScript, C, Go, Ruby, Perl, C++, PHP, and x86-64 ASM
2. **Create or refresh** the GitHub Release for that tag
3. **Release notes** come from the matching `## x.y.z` section in `CHANGELOG.md`
4. **Build and upload** native `ccc` binaries for Linux, macOS, and Windows

```bash
git tag vx.y.z
git push origin vx.y.z
# or: git push --tags
```

Tag format must match `vMAJOR.MINOR.PATCH` (optional prerelease suffix is allowed, e.g. `v0.5.0-rc.1`).

If the test gate fails, **no** GitHub Release is created and **no** binaries are uploaded.

To re-run tests + rebuild assets for an existing tag:

```bash
gh workflow run release.yml -f tag=vx.y.z
```

You do **not** need to create the GitHub Release by hand; the workflow owns that step after tests pass.

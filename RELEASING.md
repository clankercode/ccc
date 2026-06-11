# Releasing

Steps to publish a new `ccc` release.

## 1. Ensure tests pass

```bash
./test_impl.sh python
./test_impl.sh rust
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

## 7. Tag (optional)

```bash
git tag vx.y.z
git push --tags
```

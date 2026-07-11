# Releasing

Steps to publish a new `ccc` release. Agents performing a release **must** follow this full sequence, including the watch and GitHub release-notes steps at the end.

## Overview

| Step | Who | What |
|------|-----|------|
| 1–6 | Agent / human | Local tests, version bump, changelog, commit, push, crates.io publish, local install |
| 7 | Agent / human | Push version tag `vX.Y.Z` |
| 8 | GitHub Actions | Test gate → create/refresh GitHub Release → build & upload binaries |
| 9 | **Agent (required)** | Watch Actions until green; fix failures if needed |
| 10 | **Agent (required)** | Once the GitHub Release exists, populate/refresh its notes from `CHANGELOG.md` |

Do **not** stop after tagging. A release is not done until CI is green, assets are on the release, and release notes match the changelog.

---

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

Keep these three in lockstep: `VERSION`, `rust/Cargo.toml` `version`, and the tag you will push (`v` + version).

## 3. Update changelog (repo)

- `CHANGELOG.md` — move `## Unreleased` items (if any) into a new dated `## x.y.z - YYYY-MM-DD` section
- `SHARED_CHANGES.md` — add a dated entry for any shared semantic change

The GitHub Release body is derived from the `## x.y.z` section in `CHANGELOG.md`. Keep that section accurate before tagging.

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

Confirm crates.io shows the new version (API or web) before relying on `cargo install ccc`.

## 6. Install locally

```bash
just install-rs
```

Smoke-check:

```bash
ccc --version   # should report the new version
```

## 7. Tag (starts automated GitHub Release)

Pushing a version tag triggers [`.github/workflows/release.yml`](.github/workflows/release.yml):

1. **Test gate** — must pass before anything is published:
   - `VERSION` / `rust/Cargo.toml` must match the tag
   - `./test_impl.sh python` and `./test_impl.sh rust` (reference implementations + published crate)
   - Other language scaffolds are **not** in the release gate; run `./run_all_tests.sh` locally when you want the full matrix
2. **Create or refresh** the GitHub Release for that tag
3. **Draft notes** from the matching `## x.y.z` section in `CHANGELOG.md`
4. **Build and upload** native `ccc` binaries for Linux, macOS, and Windows

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
# or: git push --tags
```

Tag format must match `vMAJOR.MINOR.PATCH` (optional prerelease suffix allowed, e.g. `v0.5.0-rc.1`).

If the test gate fails, **no** new release notes/assets path completes successfully—treat that as a failed release and fix it.

To re-run tests + rebuild assets for an existing tag:

```bash
gh workflow run release.yml -f tag=vX.Y.Z
```

You do **not** need to create the GitHub Release shell by hand; Actions creates it after tests pass. You **do** need to watch CI and ensure notes are complete (steps 9–10).

---

## 8–9. Agent duty: watch GitHub Actions

After the tag is pushed (or after `gh workflow run`), the agent **must** monitor the release workflow until it finishes successfully.

### Watch commands

```bash
# Latest runs for this workflow
gh run list --workflow=release.yml --limit 5

# Follow a specific run
gh run watch <run-id>

# Or poll status
gh run view <run-id> --json status,conclusion,url,jobs

# On failure, pull failed logs
gh run view <run-id> --log-failed
```

### Agent checklist while watching

1. Confirm a `release` workflow run started for the tag (event `push` on tag, or `workflow_dispatch`).
2. Wait until **all** jobs complete: `Test gate`, `Create GitHub Release`, and each `Build binary (*)` matrix leg.
3. If anything fails:
   - Inspect logs with `gh run view … --log-failed`
   - Fix the underlying issue on a branch/commit as needed
   - Re-run with `gh workflow run release.yml -f tag=vX.Y.Z` or push a fix and re-tag only if the version content itself must change
4. Do not claim the release is done while the run is `in_progress` or `conclusion != success`.

### Verify assets

```bash
gh release view vX.Y.Z
# Expect assets similar to:
#   ccc-x86_64-unknown-linux-gnu.tar.gz
#   ccc-aarch64-apple-darwin.tar.gz   # or x86_64-apple-darwin depending on runner
#   ccc-x86_64-pc-windows-msvc.zip
```

---

## 10. Agent duty: populate GitHub release changelog

Once the GitHub Release **exists** (created by Actions or already present), the agent **must** ensure the release page body has the full changelog notes for that version—not a stub, empty body, or outdated text.

### Preferred content

Release notes should include at least:

1. Title-style heading: `## ccc X.Y.Z` (or equivalent)
2. The bullet list from `CHANGELOG.md` under `## X.Y.Z - …`
3. Install hint (`cargo install ccc`) and link to `CHANGELOG.md` on the tag

### How to populate / refresh

Extract the section from `CHANGELOG.md` and apply it with `gh release edit`:

```bash
VERSION=X.Y.Z
TAG=v$VERSION
NOTES=$(mktemp)

{
  echo "## ccc ${VERSION}"
  echo
  awk -v ver="$VERSION" '
    BEGIN { printing = 0 }
    $0 ~ ("^##[[:space:]]+" ver "([[:space:]]|$)") { printing = 1; next }
    printing && $0 ~ /^##[[:space:]]+/ { exit }
    printing { print }
  ' CHANGELOG.md
  echo
  echo "Install:"
  echo
  echo '```bash'
  echo "cargo install ccc"
  echo '```'
  echo
  echo "Or download a prebuilt binary from the assets below."
  echo
  echo "See also [CHANGELOG.md](https://github.com/clankercode/ccc/blob/${TAG}/CHANGELOG.md)."
} > "$NOTES"

gh release edit "$TAG" --title "ccc ${VERSION}" --notes-file "$NOTES"
rm -f "$NOTES"

# Confirm
gh release view "$TAG"
```

The workflow already seeds notes from `CHANGELOG.md` when it creates/refreshes the release. The agent still **verifies** the published body and re-applies from `CHANGELOG.md` if notes are missing, truncated, or wrong.

### Done criteria

A release is complete only when **all** of the following are true:

- [ ] Local Python + Rust tests passed before the bump
- [ ] Version bumped in `VERSION`, `rust/Cargo.toml`, `rust/README.md`, lockfile
- [ ] `CHANGELOG.md` / `SHARED_CHANGES.md` updated
- [ ] Commit pushed to `master`
- [ ] `cargo publish` succeeded for the new crate version
- [ ] `just install-rs` / `ccc --version` shows the new version
- [ ] Tag `vX.Y.Z` pushed
- [ ] `release` workflow **success** for that tag
- [ ] Binary assets present on the GitHub Release
- [ ] GitHub Release notes populated from `CHANGELOG.md` and verified with `gh release view`

---

## Troubleshooting

| Symptom | What to do |
|---------|------------|
| Workflow never starts | Confirm tag matches `v*` and was pushed to `origin`; check Actions tab |
| Test gate fails | Fix code/tests; re-run `gh workflow run release.yml -f tag=vX.Y.Z` after fix is on the tag tip (re-tag if the tagged commit is wrong) |
| VERSION mismatch | Ensure `VERSION` and `rust/Cargo.toml` match tag without the leading `v` |
| Release exists but no assets | Re-run workflow; check binary matrix job logs |
| Empty/wrong release notes | Re-run step 10 (`gh release edit` from `CHANGELOG.md`) |
| crates.io lags | Wait a minute after publish; `cargo install ccc` uses registry index |

---

## Related

- Workflow: [`.github/workflows/release.yml`](.github/workflows/release.yml)
- Changelog source: [`CHANGELOG.md`](CHANGELOG.md)
- Shared semantic log: [`SHARED_CHANGES.md`](SHARED_CHANGES.md)

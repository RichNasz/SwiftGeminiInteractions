---
status: alpha
---

# versioning.md — Release Lifecycle

This file is the authoritative reference for cutting SwiftGeminiInteractions releases. Consult it before any release operation.

## Version Scheme

`0.1.0-alpha.N` — semantic versioning pre-release.

- Major (`0`) and minor (`1`) are frozen during alpha.
- Only `alpha.N` increments per release.
- On promotion to beta: `0.1.0-beta.1`, `0.1.0-beta.2`, …
- On stable release: `0.1.0` (or `1.0.0` if the API surface warrants it).

**Examples:**
```
0.1.0-alpha.1   ← initial alpha
0.1.0-alpha.2   ← next alpha
0.1.0-beta.1    ← first beta
0.1.0           ← stable
```

## Where the Version String Lives

The version string (`0.1.0-alpha.N`) lives in exactly two places:

1. **Git tag** — `v0.1.0-alpha.N` on the release commit.
2. **README installation example** — the `.package(url:, from:)` line.

No other file embeds the version string. Alpha increments require only these two changes.

## Alpha Increment Procedure

When cutting `0.1.0-alpha.(N+1)`:

1. Ensure all tests pass: `swift test`
2. Update the README installation example from `0.1.0-alpha.N` to `0.1.0-alpha.(N+1)`.
3. Commit: `git commit -m "release: 0.1.0-alpha.(N+1)"`
4. Tag: `git tag -a v0.1.0-alpha.(N+1) -m "0.1.0-alpha.(N+1)"`
5. Push the tag: `git push origin v0.1.0-alpha.(N+1)`
6. Verify: `git ls-remote --tags origin "refs/tags/v0.1.0*"` — confirm the new tag appears.

No spec or doc files change for an alpha increment. The `status: alpha` frontmatter on all files was set once at the initial alpha release and remains unchanged for every subsequent alpha.

## Alpha → Beta Promotion Gate

Promote to beta when **all** are true:

- Owner has shipped at least one real application using the library.
- No known API surface issues require breaking changes.
- All integration tests pass (`RUN_INTEGRATION_TESTS=1 swift test`).

**Procedure:**

1. Update every target file's frontmatter: `status: alpha` → `status: beta`.
2. Update the README release callout and installation example to `0.1.0-beta.1`.
3. Commit: `release: 0.1.0-beta.1`
4. Tag and push `v0.1.0-beta.1`.

**Target files** (frontmatter update required on promotion):
- `Spec/` — all `.md` files
- `docs/` — all guide files (direct children only, not subdirectories)
- `docs/superpowers/specs/` — all design spec files

## Beta → Stable Promotion Gate

Promote to stable when **all** are true:

- Multiple real applications have been built and operated on the beta.
- No breaking changes anticipated.
- All integration tests pass (`RUN_INTEGRATION_TESTS=1 swift test`).

**Procedure:**

1. Update every target file's frontmatter: `status: beta` → `status: stable`.
2. Update the README release callout and installation example to `0.1.0`.
3. Commit: `release: 0.1.0`
4. Tag and push `v0.1.0`.

## Status Frontmatter Reference

Every file in `Spec/`, `docs/` (direct children), and `docs/superpowers/specs/` carries:

```yaml
---
status: <alpha|beta|stable>
---
```

This is the only frontmatter field. The specific version number is never embedded in individual spec or doc files.

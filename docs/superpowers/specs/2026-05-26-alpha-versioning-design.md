# Alpha Versioning Design

**Date:** 2026-05-26  
**Status:** approved  
**Scope:** versioning scheme, release lifecycle, per-file status markers, README update

---

## Context

SwiftGeminiInteractions is feature-complete and fully documented but has never been tagged or given a formal version. The owner wants to cut a first alpha release (`0.1.0-alpha.1`), establish a clear lifecycle for incrementing alpha versions, and define the gate for eventually promoting to beta — which requires the owner to exercise the library in real applications first.

---

## Version Scheme

**Scheme:** `0.1.0-alpha.N` (semantic versioning pre-release)

- Major (`0`) and minor (`1`) are frozen during alpha. The `0.x` major signals pre-1.0 stability.
- Patch (`0`) is frozen during alpha. Only the pre-release identifier (`alpha.N`) increments.
- `N` starts at `1` and increments for each released alpha.
- On promotion to beta: `0.1.0-beta.1`, then `0.1.0-beta.2`, etc.
- On stable release: `0.1.0` (or `1.0.0` if the API surface warrants it at that time).

**Examples:**
```
0.1.0-alpha.1   ← initial alpha
0.1.0-alpha.2   ← next alpha (bug fix or feature)
0.1.0-alpha.3   ← ...
0.1.0-beta.1    ← first beta (after owner app validation)
0.1.0           ← stable
```

---

## Where the Version String Lives

The specific version string (`0.1.0-alpha.N`) appears in exactly **two** places:

1. **Git tag** — `v0.1.0-alpha.1` on the release commit.
2. **README installation example** — the `.package(url:, from:)` line.

No other file embeds the version string. This keeps alpha increments to a two-step operation.

---

## Per-File Status Markers

All files in the following directories get YAML frontmatter with a `status:` field:

- `Spec/` (all 9 `what-*.md` and `how-*.md` files)
- `docs/` (all 8 user-facing guides)
- `docs/superpowers/specs/` (all design spec files)

**Frontmatter block:**
```yaml
---
status: alpha
---
```

**Lifecycle progression:**

| Phase | Frontmatter value |
|-------|-------------------|
| Alpha | `status: alpha`   |
| Beta  | `status: beta`    |
| Stable | `status: stable` |

Phase transitions require one pass through all target files to update the `status:` value. Alpha increments (`alpha.1` → `alpha.2`) require no file updates.

---

## New Versioning Spec File

A new file `Spec/versioning.md` is created alongside the existing `what-*.md` / `how-*.md` specs. It is the authoritative reference for the release process and must be consulted during any release operation.

Contents cover:
- The version scheme (above)
- Alpha increment procedure
- Alpha→beta promotion gate
- Beta→stable promotion gate
- Release checklist

---

## README Update

The README installation example changes from `branch: "main"` to a pinned pre-release tag:

```swift
.package(url: "https://github.com/RichNasz/SwiftGeminiInteractions", from: "0.1.0-alpha.1")
```

A brief **Release Status** callout is added near the top of the README indicating:
- Current version: `0.1.0-alpha.1`
- This is early adopter software; the API may change between alpha releases.
- Feedback and issues welcome.

---

## Alpha Increment Procedure

When cutting a new alpha (`0.1.0-alpha.N+1`):

1. Ensure all tests pass (`swift test`).
2. Update the README installation example version string.
3. Commit the README change: `release: 0.1.0-alpha.N+1`.
4. Tag: `git tag -a v0.1.0-alpha.N+1 -m "0.1.0-alpha.N+1"`.
5. Push the tag: `git push origin v0.1.0-alpha.N+1`.

No spec or doc files change for an alpha increment.

---

## Alpha → Beta Promotion Gate

Beta promotion requires **all** of the following:

- The owner has shipped at least one real application using the library.
- No known API surface issues (types, methods, behaviors) need breaking changes.
- All integration tests pass.

When the gate is met:

1. Update all target files' frontmatter: `status: alpha` → `status: beta`.
2. Update the README callout and installation example to `0.1.0-beta.1`.
3. Commit: `release: 0.1.0-beta.1`.
4. Tag and push `v0.1.0-beta.1`.

---

## Beta → Stable Promotion Gate

Stable promotion requires **all** of the following:

- Multiple real applications have been built and operated on the beta.
- No breaking changes are anticipated in the near term.
- All integration tests pass.

When the gate is met:

1. Update all target files' frontmatter: `status: beta` → `status: stable`.
2. Update the README callout and installation example to `0.1.0`.
3. Commit: `release: 0.1.0`.
4. Tag and push `v0.1.0`.

---

## Files Modified by This Design

| File | Change |
|------|--------|
| `Spec/versioning.md` | New file |
| `Spec/what-core.md` | Add frontmatter |
| `Spec/what-toolsession.md` | Add frontmatter |
| `Spec/what-agent.md` | Add frontmatter |
| `Spec/how-client.md` | Add frontmatter |
| `Spec/how-encoding.md` | Add frontmatter |
| `Spec/how-streaming.md` | Add frontmatter |
| `Spec/how-toolloop.md` | Add frontmatter |
| `Spec/how-polling.md` | Add frontmatter |
| `Spec/how-errors.md` | Add frontmatter |
| `docs/getting-started.md` | Add frontmatter |
| `docs/streaming.md` | Add frontmatter |
| `docs/tools.md` | Add frontmatter |
| `docs/agent.md` | Add frontmatter |
| `docs/configuration.md` | Add frontmatter |
| `docs/error-handling.md` | Add frontmatter |
| `docs/background-and-polling.md` | Add frontmatter |
| `docs/traits.md` | Add frontmatter |
| `docs/superpowers/specs/*.md` | Add frontmatter (5 files) |
| `README.md` | Update installation + add status callout |

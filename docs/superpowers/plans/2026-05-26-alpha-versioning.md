# Alpha Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish `0.1.0-alpha.1` as the first formal release by creating the versioning spec, adding `status: alpha` frontmatter to all spec and doc files, updating the README, and tagging the release commit.

**Architecture:** Version identity lives in exactly two places — the git tag and the README installation example. All spec/doc files carry only a `status: alpha` frontmatter field that advances through `alpha → beta → stable` on phase transitions, never on individual alpha increments.

**Tech Stack:** Markdown files, git tags, Python 3 (for frontmatter prepend script).

---

### Task 1: Create `Spec/versioning.md`

**Files:**
- Create: `Spec/versioning.md`

- [ ] **Step 1: Write `Spec/versioning.md`**

Create the file with the exact content below. This is the authoritative release reference — it must be complete and unambiguous.

```markdown
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
\```
0.1.0-alpha.1   ← initial alpha
0.1.0-alpha.2   ← next alpha
0.1.0-beta.1    ← first beta
0.1.0           ← stable
\```

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

No spec or doc files change for an alpha increment.

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

\```yaml
---
status: <alpha|beta|stable>
---
\```

This is the only frontmatter field. The specific version number is never embedded in individual spec or doc files.
```

- [ ] **Step 2: Verify the file exists**

```bash
head -5 Spec/versioning.md
```

Expected output:
```
---
status: alpha
---

# versioning.md — Release Lifecycle
```

---

### Task 2: Add frontmatter to all `Spec/` files

**Files:**
- Modify: `Spec/what-core.md`, `Spec/what-toolsession.md`, `Spec/what-agent.md`, `Spec/how-client.md`, `Spec/how-encoding.md`, `Spec/how-streaming.md`, `Spec/how-toolloop.md`, `Spec/how-polling.md`, `Spec/how-errors.md`

(Skip `Spec/versioning.md` — it was created with frontmatter in Task 1.)

- [ ] **Step 1: Prepend `status: alpha` frontmatter to the 9 existing Spec/ files**

Run from the repo root:

```bash
python3 << 'PYEOF'
import glob

targets = [
    "Spec/what-core.md",
    "Spec/what-toolsession.md",
    "Spec/what-agent.md",
    "Spec/how-client.md",
    "Spec/how-encoding.md",
    "Spec/how-streaming.md",
    "Spec/how-toolloop.md",
    "Spec/how-polling.md",
    "Spec/how-errors.md",
]

for path in targets:
    content = open(path).read()
    if not content.startswith("---\n"):
        open(path, "w").write("---\nstatus: alpha\n---\n\n" + content)
        print(f"Updated: {path}")
    else:
        print(f"Skipped (already has frontmatter): {path}")
PYEOF
```

Expected output:
```
Updated: Spec/what-core.md
Updated: Spec/what-toolsession.md
Updated: Spec/what-agent.md
Updated: Spec/how-client.md
Updated: Spec/how-encoding.md
Updated: Spec/how-streaming.md
Updated: Spec/how-toolloop.md
Updated: Spec/how-polling.md
Updated: Spec/how-errors.md
```

- [ ] **Step 2: Spot-check two files**

```bash
head -4 Spec/what-core.md && echo "---" && head -4 Spec/how-client.md
```

Expected: both start with `---`, `status: alpha`, `---`, blank line, then the original `#` heading.

---

### Task 3: Add frontmatter to all `docs/` guide files

**Files:**
- Modify: `docs/getting-started.md`, `docs/streaming.md`, `docs/tools.md`, `docs/agent.md`, `docs/configuration.md`, `docs/error-handling.md`, `docs/background-and-polling.md`, `docs/traits.md`

- [ ] **Step 1: Prepend `status: alpha` frontmatter to the 8 docs/ guide files**

Run from the repo root:

```bash
python3 << 'PYEOF'
targets = [
    "docs/getting-started.md",
    "docs/streaming.md",
    "docs/tools.md",
    "docs/agent.md",
    "docs/configuration.md",
    "docs/error-handling.md",
    "docs/background-and-polling.md",
    "docs/traits.md",
]

for path in targets:
    content = open(path).read()
    if not content.startswith("---\n"):
        open(path, "w").write("---\nstatus: alpha\n---\n\n" + content)
        print(f"Updated: {path}")
    else:
        print(f"Skipped (already has frontmatter): {path}")
PYEOF
```

Expected output: `Updated:` for all 8 files.

- [ ] **Step 2: Spot-check**

```bash
head -4 docs/getting-started.md
```

Expected:
```
---
status: alpha
---

```

---

### Task 4: Add frontmatter to all `docs/superpowers/specs/` design files

**Files:**
- Modify: all `.md` files in `docs/superpowers/specs/`

There are currently 6 files (5 pre-existing design specs + the alpha-versioning design spec committed in the brainstorming session). The script handles all of them.

- [ ] **Step 1: Prepend `status: alpha` frontmatter to all design spec files**

Run from the repo root:

```bash
python3 << 'PYEOF'
import glob

targets = sorted(glob.glob("docs/superpowers/specs/*.md"))

for path in targets:
    content = open(path).read()
    if not content.startswith("---\n"):
        open(path, "w").write("---\nstatus: alpha\n---\n\n" + content)
        print(f"Updated: {path}")
    else:
        print(f"Skipped (already has frontmatter): {path}")
PYEOF
```

Expected: `Updated:` for all 6 files (none have YAML frontmatter yet — they use prose `**Status:**` lines, which is different and won't conflict).

- [ ] **Step 2: Spot-check**

```bash
head -4 docs/superpowers/specs/2026-05-24-gemini-interactions-design.md
```

Expected:
```
---
status: alpha
---

```

---

### Task 5: Update `README.md`

**Files:**
- Modify: `README.md`

Two changes: (1) switch the installation example from `branch: "main"` to `from: "0.1.0-alpha.1"`, and (2) add a Release Status section after the opening paragraph.

- [ ] **Step 1: Update the installation example**

In `README.md`, replace:

```swift
    .package(url: "https://github.com/RichNasz/SwiftGeminiInteractions.git", branch: "main")
```

With:

```swift
    .package(url: "https://github.com/RichNasz/SwiftGeminiInteractions.git", from: "0.1.0-alpha.1")
```

- [ ] **Step 2: Add a Release Status section**

Insert the following block **between** the opening paragraph and the `## Install` heading:

```markdown
## Release Status

**0.1.0-alpha.1** — Early adopter software. The API may change between alpha releases as it is exercised in real applications. Feedback and issues are welcome.
```

The README should now read:

```markdown
# SwiftGeminiInteractions

A Swift client for the [Gemini Interactions API](https://ai.google.dev/gemini-api/docs/interactions) — send requests, stream responses, call tools, and run multi-turn agents.

## Release Status

**0.1.0-alpha.1** — Early adopter software. The API may change between alpha releases as it is exercised in real applications. Feedback and issues are welcome.

## Install

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/RichNasz/SwiftGeminiInteractions.git", from: "0.1.0-alpha.1")
]
```
```

- [ ] **Step 3: Verify the README looks correct**

```bash
head -20 README.md
```

Confirm: `## Release Status` section is present, `from: "0.1.0-alpha.1"` appears in the install block, `branch: "main"` is gone.

---

### Task 6: Commit and tag `v0.1.0-alpha.1`

**Files:** all modified files staged together.

- [ ] **Step 1: Stage all changes**

```bash
git add Spec/ docs/ README.md
```

- [ ] **Step 2: Verify the staged file list**

```bash
git diff --cached --name-only
```

Expected — 25 files total:
```
README.md
Spec/how-client.md
Spec/how-encoding.md
Spec/how-errors.md
Spec/how-polling.md
Spec/how-streaming.md
Spec/how-toolloop.md
Spec/versioning.md
Spec/what-agent.md
Spec/what-core.md
Spec/what-toolsession.md
docs/agent.md
docs/background-and-polling.md
docs/configuration.md
docs/error-handling.md
docs/getting-started.md
docs/streaming.md
docs/superpowers/specs/2026-05-24-gemini-interactions-design.md
docs/superpowers/specs/2026-05-25-documentation-design.md
docs/superpowers/specs/2026-05-25-gemini-macros-design.md
docs/superpowers/specs/2026-05-25-package-traits-design.md
docs/superpowers/specs/2026-05-26-alpha-versioning-design.md
docs/superpowers/specs/2026-05-26-open-source-community-health-design.md
docs/tools.md
docs/traits.md
```

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
release: 0.1.0-alpha.1

- Add Spec/versioning.md with release lifecycle and promotion gates
- Add status: alpha frontmatter to all Spec/, docs/, and design spec files
- Update README install example to pin from: 0.1.0-alpha.1
- Add README Release Status callout

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Tag the release**

```bash
git tag -a v0.1.0-alpha.1 -m "0.1.0-alpha.1"
```

- [ ] **Step 5: Verify the tag**

```bash
git tag -l "v0.1.0*"
```

Expected:
```
v0.1.0-alpha.1
```

- [ ] **Step 6: Push the tag**

```bash
git push origin v0.1.0-alpha.1
```

Expected: tag appears on the remote. Confirm with:

```bash
git ls-remote --tags origin "refs/tags/v0.1.0*"
```

Expected output includes `refs/tags/v0.1.0-alpha.1`.

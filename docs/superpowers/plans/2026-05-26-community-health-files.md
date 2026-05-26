# Community Health Files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `.github/CONTRIBUTING.md`, `.github/CODE_OF_CONDUCT.md`, and `.github/SECURITY.md` to make SwiftGeminiInteractions a properly structured public open source project.

**Architecture:** Three standalone markdown files placed in `.github/` — GitHub surfaces them automatically at the right moments (issue/PR creation, Security tab, Insights tab). No code changes, no build system changes, no README changes required.

**Tech Stack:** Markdown, Git

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `.github/CONTRIBUTING.md` | Create | How to file bugs and feature requests; why code PRs aren't accepted |
| `.github/CODE_OF_CONDUCT.md` | Create | Minimal plain-language community norms |
| `.github/SECURITY.md` | Create | Where and how to report security vulnerabilities |

---

### Task 1: Create `.github/CONTRIBUTING.md`

**Files:**
- Create: `.github/CONTRIBUTING.md`

- [ ] **Step 1: Create the `.github/` directory and write CONTRIBUTING.md**

Create the directory and file with this exact content:

```markdown
# Contributing to SwiftGeminiInteractions

Thanks for your interest in SwiftGeminiInteractions. Contributions via GitHub Issues are welcome.

## Reporting Bugs

Open a [GitHub Issue](https://github.com/RichNasz/SwiftGeminiInteractions/issues). Please include:

- What you expected to happen
- What actually happened
- Your Swift version and platform (macOS/iOS)
- A minimal code snippet that reproduces the problem

## Requesting Features

Open a [GitHub Issue](https://github.com/RichNasz/SwiftGeminiInteractions/issues). Describe what you want and why — not how to implement it. The best feature requests focus on the problem to solve, not a specific solution.

## Why Not Code PRs?

This project uses a spec-driven development model: all changes begin as written specifications before any code is written. Unsolicited code PRs skip the design step and can't be accepted. Feature ideas raised via issues may be implemented in a future release when they align with the project's direction.
```

- [ ] **Step 2: Verify the file exists**

Run:
```bash
cat .github/CONTRIBUTING.md
```

Expected: full file content printed with no truncation.

- [ ] **Step 3: Commit**

```bash
git add .github/CONTRIBUTING.md
git commit -m "docs: add CONTRIBUTING.md"
```

Expected: `1 file changed, 1 insertion(+)` or similar.

---

### Task 2: Create `.github/CODE_OF_CONDUCT.md`

**Files:**
- Create: `.github/CODE_OF_CONDUCT.md`

- [ ] **Step 1: Write CODE_OF_CONDUCT.md**

Create `.github/CODE_OF_CONDUCT.md` with this exact content:

```markdown
# Code of Conduct

Be respectful to everyone in issues, discussions, and other project spaces. Assume good intent. Keep feedback focused on code and ideas, not on people.

If something feels wrong, contact [richard@naszcyniec.com](mailto:richard@naszcyniec.com).
```

- [ ] **Step 2: Verify the file exists**

Run:
```bash
cat .github/CODE_OF_CONDUCT.md
```

Expected: full file content printed.

- [ ] **Step 3: Commit**

```bash
git add .github/CODE_OF_CONDUCT.md
git commit -m "docs: add CODE_OF_CONDUCT.md"
```

Expected: `1 file changed, 1 insertion(+)` or similar.

---

### Task 3: Create `.github/SECURITY.md`

**Files:**
- Create: `.github/SECURITY.md`

- [ ] **Step 1: Write SECURITY.md**

Create `.github/SECURITY.md` with this exact content:

```markdown
# Security Policy

## Reporting a Vulnerability

Please do not file public GitHub Issues for security vulnerabilities.

**Preferred:** Use [GitHub's private security advisory](https://github.com/RichNasz/SwiftGeminiInteractions/security/advisories/new) — Security tab → "Report a vulnerability."

**Alternative:** Email [richard@naszcyniec.com](mailto:richard@naszcyniec.com) directly.

## What to Include

- A description of the vulnerability
- Steps to reproduce
- Affected versions, if known

## Response

I aim to respond within 7 days of receiving a report.
```

- [ ] **Step 2: Verify the file exists**

Run:
```bash
cat .github/SECURITY.md
```

Expected: full file content printed.

- [ ] **Step 3: Commit**

```bash
git add .github/SECURITY.md
git commit -m "docs: add SECURITY.md"
```

Expected: `1 file changed, 1 insertion(+)` or similar.

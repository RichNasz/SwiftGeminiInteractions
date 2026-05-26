# Open Source Community Health Files — Design

**Date:** 2026-05-26
**Status:** Approved
**Audience:** Richard Naszcyniec (maintainer), future contributors

## Goal

Add three community health files to make SwiftGeminiInteractions a properly structured open source project ready to share publicly via `github.com/RichNasz/SwiftGeminiInteractions`. The files set clear contribution expectations, establish basic community norms, and document the security reporting path.

## Scope

Three files only. No CI, no issue templates, no CHANGELOG, no release automation — those are separate concerns for future specs.

---

## File Placement

All three files go in `.github/` at the repo root. GitHub automatically surfaces them:
- `CONTRIBUTING.md` → linked when someone opens an issue or PR
- `CODE_OF_CONDUCT.md` → shown in the Insights tab
- `SECURITY.md` → shown in the Security tab

No additional linking or README changes required.

---

## 1. `.github/CONTRIBUTING.md`

**Tone:** Welcoming, honest, brief. Sets expectations without bureaucracy.

**Structure:**

### Thanks
One sentence thanking contributors for their interest.

### Reporting Bugs
Open a GitHub Issue. Include:
- What you expected to happen
- What actually happened
- Swift version and platform (macOS/iOS)
- A minimal code snippet that reproduces the problem

### Requesting Features
Open a GitHub Issue. Describe what you want and why — not how to implement it. The project's development model starts with design, not code.

### Why Not Code PRs
2–3 sentences explaining the spec-driven model: all changes begin as specifications before any code is written. Unsolicited code PRs skip the design step and can't be accepted. Feature ideas raised via issues may be implemented in a future release.

---

## 2. `.github/CODE_OF_CONDUCT.md`

**Tone:** Plain English, human, not legalistic.

**Content:** Short — roughly 3–4 sentences total:
- Be respectful to everyone in issues, PRs, and discussions
- Assume good intent
- Keep feedback about code and ideas, not about people
- If something feels wrong, contact richard@naszcyniec.com

No enumerated violation categories, no lengthy enforcement procedures, no Contributor Covenant boilerplate.

---

## 3. `.github/SECURITY.md`

**Tone:** Direct and practical.

**Structure:**

### Reporting a Vulnerability
- **Preferred:** Use GitHub's private security advisory — Security tab → "Report a vulnerability"
- **Alternative:** Email richard@naszcyniec.com directly
- Do not file public GitHub Issues for security vulnerabilities

### What to Include
- Description of the vulnerability
- Steps to reproduce
- Affected versions (if known)

### Response
Aim to respond within 7 days of receiving a report.

---

## What This Does Not Cover

- GitHub Actions CI — future spec
- Issue templates — future spec if needed
- PR templates — future spec if needed
- Versioning and release process — future spec
- CHANGELOG — future spec

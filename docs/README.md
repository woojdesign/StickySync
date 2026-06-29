# StickySync — docs

Project documentation, research, and planning notes. Live, internal-facing.
User-facing release notes live in `/release-notes/` at the repo root (tied to
the release pipeline; intentionally separate).

## Layout

- [`testing.md`](testing.md) — testing discipline: rules + cadence. The "every
  bug gets a failing test before it gets a fix" doc.
- [`plans/`](plans/) — design + spec docs for features in flight or under
  consideration. Each file is a self-contained plan; once a feature ships,
  the file stays as the historical record.
  - [`plans/capture-merge.md`](plans/capture-merge.md) — folding the standalone
    Capture app into `StickySyncMobile`. Phase 0 shipped; later phases pending.

## What goes where

- **`docs/`** (this dir) — anything you'd hand someone to explain *why* a piece
  of the system exists or *what we're considering*. Design docs, plans,
  process rules, decision records, research notes.
- **`release-notes/<version>.md`** — the user-facing changelog for that
  version. Generated + lightly edited by `scripts/release_notes.sh`; consumed
  by `release.sh` (GH Release body) and `testflight.sh` ("What to Test").
- **`CLAUDE.md`** at repo root — operational guide for the AI working in this
  repo, also useful as a high-level orientation for a new human contributor.
  Auto-loaded every session.
- **`scripts/`** — release + build helpers (bash + python). Implementation,
  not docs.

## When to add a doc here

- New feature with non-obvious tradeoffs → `plans/<feature>.md` *before*
  starting code. Captures the decision space so future-you knows why we
  picked path A over B.
- Process / discipline rule that affects how we ship → top-level (like
  `testing.md`).
- One-off research that informed a decision and might be useful again →
  `plans/` is fine; rename to something descriptive.

What does NOT belong here: ephemeral session notes, in-progress task lists
(use the conversation), per-commit explanations (use the commit message).

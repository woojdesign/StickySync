#!/usr/bin/env bash
#
# Generate release notes for an upcoming version.
#
# Pulls commits since the most recent tag, sends them through `claude -p` to be
# rewritten as a user-facing, platform-grouped changelog, writes
# release-notes/<version>.md, and opens it in $EDITOR for a final pass.
#
# Usage:
#   ./scripts/release_notes.sh <version>
#   ./scripts/release_notes.sh <version> --platform mac|ios|all
#   ./scripts/release_notes.sh <version> --no-edit
#   ./scripts/release_notes.sh <version> --since <git-rev>
#
# The polished output is plain Markdown — no preamble — so it can be embedded
# in a GitHub release, TestFlight "What to Test", or a Sparkle appcast.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: $0 <version> [--platform mac|ios|all] [--no-edit] [--since <rev>]"; exit 1; }
shift

PLATFORM="all"
EDIT=1
SINCE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --platform) PLATFORM="$2"; shift 2 ;;
        --no-edit)  EDIT=0; shift ;;
        --since)    SINCE="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

# Range: explicit --since wins, otherwise last tag..HEAD, otherwise all of HEAD.
if [ -n "$SINCE" ]; then
    RANGE="$SINCE..HEAD"
else
    LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    RANGE="${LAST_TAG:+$LAST_TAG..HEAD}"
    RANGE="${RANGE:-HEAD}"
fi

COMMITS="$(git log $RANGE --no-merges --pretty='- %s')"
if [ -z "$COMMITS" ]; then
    echo "No commits in $RANGE — nothing to write." >&2
    exit 1
fi

mkdir -p release-notes
OUT="release-notes/$VERSION.md"

command -v claude >/dev/null 2>&1 || { echo "error: \`claude\` CLI not on PATH"; exit 1; }

PLATFORM_RULE=""
case "$PLATFORM" in
    mac) PLATFORM_RULE="This release is Mac-only — drop any iOS-only changes. Do not group by platform; produce a single bulleted list." ;;
    ios) PLATFORM_RULE="This release is iOS-only — drop any Mac-only changes. Do not group by platform; produce a single bulleted list." ;;
    all) PLATFORM_RULE="Group changes under '## Mac', '## iOS', and '## Shared' subheadings. Omit any group with no entries." ;;
    *) echo "--platform must be mac|ios|all" >&2; exit 1 ;;
esac

PROMPT="You are writing release notes for StickySync $VERSION. Below is the list of git commits since the last release. Rewrite them as a concise, user-facing changelog.

Rules:
- ${PLATFORM_RULE}
- One bullet per user-visible change. Drop pure-internal commits (refactors, gitignore, CI, build-only changes) unless they meaningfully affect the user.
- Past tense, neutral voice. Example: 'Added a Share button on the note strip.'
- Commit messages may be prefixed with 'Mac:', 'iOS:', 'Capture:' — use those as platform hints, then strip the prefix from the user-facing bullet.
- No preamble, no closing remarks. Start the output with the first bullet (or first heading). Markdown only.
- Keep the whole output under 3500 characters (TestFlight limit is 4000).

Commits:
$COMMITS"

echo "==> Polishing $(printf '%s\n' "$COMMITS" | wc -l | tr -d ' ') commit(s) via claude -p (range: $RANGE)"
printf '%s' "$PROMPT" | claude -p > "$OUT"

# Strip a leading fenced-code block if claude wraps the output (it shouldn't, but be safe).
if head -1 "$OUT" | grep -q '^```'; then
    sed -i.bak -e '1d' -e '$d' "$OUT" && rm -f "$OUT.bak"
fi

if [ "$EDIT" = "1" ] && [ -t 1 ]; then
    "${EDITOR:-vi}" "$OUT"
fi

echo "==> Wrote $OUT ($(wc -c < "$OUT" | tr -d ' ') chars)"

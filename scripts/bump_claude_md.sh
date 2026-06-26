#!/usr/bin/env bash
# Keep the "Last shipped" lines in CLAUDE.md truthful — called at the end
# of every successful ship so future Claude sessions read the right version.
# Inaccurate docs are worse than no docs.
#
# Usage:
#   bump_claude_md.sh mac <version>
#   bump_claude_md.sh ios <version> <build>
#
# Matches the literal "Last shipped: **X.Y.Z**." line on Mac and the
# "Last shipped: **X.Y.Z (N)** as `ios/vX.Y.Z`." line on iOS — both forms
# are distinctive enough that the pattern can't cross-match.

set -euo pipefail

PLATFORM="${1:-}"
VERSION="${2:-}"
BUILD="${3:-}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$REPO_ROOT/CLAUDE.md"
[ -f "$DOC" ] || { echo "bump_claude_md: no CLAUDE.md at $DOC — skipping"; exit 0; }
[ -n "$VERSION" ] || { echo "bump_claude_md: missing version arg" >&2; exit 1; }

case "$PLATFORM" in
    mac)
        sed -i '' -E \
            "s/Last shipped: \\*\\*[0-9]+\\.[0-9]+\\.[0-9]+\\*\\*\\./Last shipped: **${VERSION}**./" \
            "$DOC"
        ;;
    ios)
        [ -n "$BUILD" ] || { echo "bump_claude_md: ios needs <build> arg" >&2; exit 1; }
        # Single-quoted sed expression so backticks and `**` don't get
        # interpreted by the shell — variables are spliced in via the
        # close-open-close pattern.
        sed -i '' -E \
            's|Last shipped: \*\*[0-9]+\.[0-9]+\.[0-9]+ \([0-9]+\)\*\* as `ios/v[0-9]+\.[0-9]+\.[0-9]+`\.|Last shipped: **'"${VERSION}"' ('"${BUILD}"')** as `ios/v'"${VERSION}"'`.|' \
            "$DOC"
        ;;
    *)
        echo "usage: $0 mac|ios <version> [<build>]" >&2
        exit 1
        ;;
esac

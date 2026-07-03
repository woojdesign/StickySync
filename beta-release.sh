#!/usr/bin/env bash
#
# 0.11.1: cut a BETA release for the Sparkle beta channel.
#
# Parallel to release.sh but doesn't touch the stable feed:
#   build → Developer ID sign → notarize → staple → EdDSA-sign →
#   channel-tagged appcast → beta GitHub Release (prerelease).
#
# The beta feed lives at a fixed URL:
#   https://github.com/woojdesign/StickySync/releases/download/beta-feed/appcast.xml
#
# The `beta-feed` tag is a rolling release that gets its assets
# overwritten on every beta ship (so the URL above is always the
# newest beta appcast). The versioned prerelease (v0.11.1-beta1
# etc.) is kept separately for history + rollback.
#
# Usage:
#   ./beta-release.sh 0.11.1-beta1
#
# Prereqs: same as release.sh (notarize.sh + Sparkle key + gh auth).
#
# To subscribe a Mac to beta:
#   defaults write wooj.StickySync SUFeedURL \
#     "https://github.com/woojdesign/StickySync/releases/download/beta-feed/appcast.xml"
#   defaults write wooj.StickySync SUAllowedChannels -array beta
# Or use the app's Debug → Beta Channel menu toggle (0.11.1+).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="${1:?usage: ./beta-release.sh <version>   e.g. 0.11.1-beta1}"
TAG="v$VERSION"
BETA_FEED_TAG="beta-feed"
REPO="woojdesign/StickySync"

# 1. Notes — reuse the same generator; the beta appcast body just
#    surfaces the same commit summary as would land in stable.
./scripts/release_notes.sh "$VERSION" --platform mac
CHANGELOG="release-notes/$VERSION.md"
[ -f "$CHANGELOG" ] || { echo "error: $CHANGELOG missing"; exit 1; }

# 2. Build + notarize (same signing pipeline).
./notarize.sh "$VERSION"

BUILD_NUMBER="$(git rev-list --count HEAD)"
ZIP="build/StickySync-$VERSION-$BUILD_NUMBER.zip"
[ -f "$ZIP" ] || { echo "error: expected $ZIP from notarize.sh"; exit 1; }

# 3. EdDSA-sign + build appcast, then inject the beta channel tag.
GEN_APPCAST="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type f -name generate_appcast -path '*artifacts/sparkle*' 2>/dev/null | head -1)"
[ -n "$GEN_APPCAST" ] || { echo "error: Sparkle generate_appcast not found"; exit 1; }

RELEASES="build/releases-beta"
rm -rf "$RELEASES"; mkdir -p "$RELEASES"
cp "$ZIP" "$RELEASES/"
echo "==> Signing update + generating appcast"
"$GEN_APPCAST" "$RELEASES" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/"
APPCAST="$RELEASES/appcast.xml"
[ -f "$APPCAST" ] || { echo "error: appcast.xml not generated"; exit 1; }

# Inject <sparkle:channel>beta</sparkle:channel> into every <item>.
# Sparkle's client-side channel filter (SUAllowedChannels) then hides
# these items from users on the stable channel.
python3 <<PYEOF
import re, sys, pathlib
p = pathlib.Path("$APPCAST")
xml = p.read_text()
if "<sparkle:channel>" not in xml:
    xml = re.sub(r"(<item>)",
                 r"\1\n            <sparkle:channel>beta</sparkle:channel>",
                 xml, count=0)
p.write_text(xml)
print("beta channel tag injected into", len(re.findall(r"<sparkle:channel>beta", xml)), "item(s)")
PYEOF

# 4. Publish the versioned prerelease (history + rollback anchor).
echo "==> Publishing versioned prerelease $TAG"
gh release create "$TAG" \
    "$RELEASES/$(basename "$ZIP")" \
    --repo "$REPO" \
    --prerelease \
    --title "StickySync $VERSION (Beta)" \
    --notes-file "$CHANGELOG"

# 5. Publish/overwrite the rolling `beta-feed` release. The zip AND
#    the tagged appcast live here so the fixed feed URL always points
#    at the latest beta build.
echo "==> Refreshing rolling beta-feed release"
# Delete-and-recreate is the simplest way to guarantee assets get
# overwritten regardless of gh's cache.
gh release delete "$BETA_FEED_TAG" --repo "$REPO" --yes 2>/dev/null || true
git push --delete origin "$BETA_FEED_TAG" 2>/dev/null || true
gh release create "$BETA_FEED_TAG" \
    "$RELEASES/$(basename "$ZIP")" \
    "$APPCAST" \
    --repo "$REPO" \
    --prerelease \
    --title "StickySync Beta Feed (rolling)" \
    --notes "Rolling beta feed — assets are overwritten on every beta ship. Beta channel: $VERSION."

echo
echo "Beta released $TAG."
echo "  Beta feed URL: https://github.com/$REPO/releases/download/$BETA_FEED_TAG/appcast.xml"
echo "  Subscribe:     defaults write wooj.StickySync SUFeedURL \\"
echo "                     \"https://github.com/$REPO/releases/download/$BETA_FEED_TAG/appcast.xml\""
echo "                 defaults write wooj.StickySync SUAllowedChannels -array beta"
echo "  Or use the app's Debug → Beta Channel menu toggle (0.11.1+)."

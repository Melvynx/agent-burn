#!/bin/bash
# Build, notarize and publish exactly a pushed commit. Never publishes local edits.
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
version="$(cat apps/macos/Config/version)"
tag="macos-v$version"
repo="${AGENT_BURN_REPOSITORY:-Melvynx/agent-burn}"
commit="$(git rev-parse HEAD)"
branch="$(git branch --show-current)"
if [[ "$(git ls-remote origin "refs/heads/$branch" | cut -f1)" != "$commit" ]]; then
  echo "Push the release commit before publishing." >&2; exit 1
fi
if ! git diff --quiet HEAD -- apps/macos rust; then echo "Commit app and CLI changes first." >&2; exit 1; fi
existing_draft="$(gh release view "$tag" --repo "$repo" --json isDraft --jq .isDraft 2>/dev/null || true)"
if [[ "$existing_draft" == false ]]; then echo "$tag is already published" >&2; exit 1; fi
key="${AGENT_BURN_SPARKLE_KEY_FILE:?Set AGENT_BURN_SPARKLE_KEY_FILE to your private Ed25519 seed file}"
: "${AGENT_BURN_SIGN_IDENTITY:?Set a Developer ID Application identity}"
work="$(mktemp -d "${TMPDIR:-/tmp}/agent-burn-release.XXXXXX")"
trap 'rm -rf "$work"' EXIT
git archive HEAD | tar -x -C "$work"
cd "$work/apps/macos"
./build.sh --release
archive="$PWD/dist/Agent-Burn-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent 'dist/Agent Burn.app' "$archive"
if [[ -n "${AGENT_BURN_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$archive" --keychain-profile "$AGENT_BURN_NOTARY_PROFILE" --wait
else
  asc notarization submit --file "$archive" --wait --timeout 1h
fi
xcrun stapler staple 'dist/Agent Burn.app'
xcrun stapler validate 'dist/Agent Burn.app'
spctl --assess --type execute 'dist/Agent Burn.app'
rm "$archive"
ditto -c -k --sequesterRsrc --keepParent 'dist/Agent Burn.app' "$archive"
generator="$(find .build/artifacts -type f -name generate_appcast -print -quit)"
mkdir dist/feed
cp "$archive" dist/feed/
"$generator" --ed-key-file "$key" --download-url-prefix "https://github.com/$repo/releases/download/$tag/" --link 'https://agent-burn.melvynx.dev' dist/feed
cp dist/feed/appcast.xml dist/appcast.xml
(cd dist && shasum -a 256 Agent-Burn-macOS.zip > SHA256SUMS)
notes="Universal macOS 14+ app. Developer ID signed and notarized. Includes the native CLI and signed Sparkle updates. Source is attached to this release tag."
if [[ "$existing_draft" == true ]]; then
  gh release upload "$tag" dist/Agent-Burn-macOS.zip dist/appcast.xml dist/SHA256SUMS --repo "$repo" --clobber
  gh release edit "$tag" --repo "$repo" --target "$commit" --notes "$notes" --draft=false --latest=false
else
  gh release create "$tag" dist/Agent-Burn-macOS.zip dist/appcast.xml dist/SHA256SUMS --repo "$repo" --target "$commit" --title "Agent Burn for macOS $version" --notes "$notes" --latest=false
fi
# The stable channel is separate from CLI releases. Appcast enclosures point to
# immutable versioned archives, even while this discovery channel advances.
if ! gh release view macos --repo "$repo" >/dev/null 2>&1; then
  gh release create macos --repo "$repo" --target "$commit" --title 'macOS download channel' --notes 'Current Mac download and signed update feed. Versioned source and archives are in macos-v* releases.' --prerelease --latest=false
fi
gh release upload macos dist/Agent-Burn-macOS.zip dist/appcast.xml dist/SHA256SUMS --repo "$repo" --clobber
mkdir -p "$root/apps/macos/dist"
cp dist/{Agent-Burn-macOS.zip,appcast.xml,SHA256SUMS} "$root/apps/macos/dist/"

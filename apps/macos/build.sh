#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
release=0
[[ "${1:-}" != "--release" ]] || release=1
version="$(tr -d '\n' < Config/version)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "Invalid version" >&2; exit 1; fi
swift_args=(--disable-keychain -c release)
if [[ "$release" == 1 ]]; then
  swift build "${swift_args[@]}" --triple arm64-apple-macosx14.0
  swift build "${swift_args[@]}" --triple x86_64-apple-macosx14.0
  cargo build --manifest-path ../../rust/Cargo.toml --release --bin agent-burn --target aarch64-apple-darwin
  cargo build --manifest-path ../../rust/Cargo.toml --release --bin agent-burn --target x86_64-apple-darwin
  bin="$(swift build "${swift_args[@]}" --triple arm64-apple-macosx14.0 --show-bin-path)"
  intel="$(swift build "${swift_args[@]}" --triple x86_64-apple-macosx14.0 --show-bin-path)"
else
  if [[ -z "${AGENT_BURN_CLI:-}" ]]; then
    cargo build --manifest-path ../../rust/Cargo.toml --release --bin agent-burn
  fi
  cli="${AGENT_BURN_CLI:-../../rust/target/release/agent-burn}"
  swift build "${swift_args[@]}"
  bin="$(swift build "${swift_args[@]}" --show-bin-path)"
fi
# Assemble in a new directory so obsolete frameworks cannot survive a rebuild.
staging="$(mktemp -d "$PWD/dist-staging.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Agent Burn.app"
mkdir -p "$app/Contents/"{MacOS,Resources,Frameworks} dist
if [[ "$release" == 1 ]]; then
  lipo -create "$bin/AgentBurn" "$intel/AgentBurn" -output "$app/Contents/MacOS/AgentBurn"
  lipo -create ../../rust/target/{aarch64-apple-darwin,x86_64-apple-darwin}/release/agent-burn -output "$app/Contents/Resources/agent-burn"
else
  cp "$bin/AgentBurn" "$app/Contents/MacOS/AgentBurn"
  cp "$cli" "$app/Contents/Resources/agent-burn"
fi
ditto "$bin/AgentBurn_AgentBurn.bundle" "$app/Contents/Resources/AgentBurn_AgentBurn.bundle"
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$app/Contents/MacOS/AgentBurn"
cp Assets/Logo/AgentBurn.icns "$app/Contents/Resources/AgentBurn.icns"
cp ../../LICENSE "$app/Contents/Resources/LICENSE.txt"
cp .build/checkouts/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.melvynx.agent-burn</string>
<key>CFBundleName</key><string>Agent Burn</string>
<key>CFBundleDisplayName</key><string>Agent Burn</string>
<key>CFBundleExecutable</key><string>AgentBurn</string>
<key>CFBundleIconFile</key><string>AgentBurn</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
<key>SUFeedURL</key><string>https://agent-burn.melvynx.dev/appcast.xml</string>
<key>SUPublicEDKey</key><string>$(tr -d '\n' < Config/sparkle-public-key)</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUScheduledCheckInterval</key><integer>86400</integer>
<key>SUSendProfileInfo</key><false/>
</dict></plist>
PLIST
identity="${AGENT_BURN_SIGN_IDENTITY:--}"
flags=(--force --sign "$identity")
if [[ "$release" == 1 ]]; then
  if [[ "$identity" == - ]]; then echo "Set AGENT_BURN_SIGN_IDENTITY to a Developer ID identity" >&2; exit 1; fi
  flags+=(--options runtime --timestamp)
fi
codesign "${flags[@]}" "$app/Contents/Resources/agent-burn"
# Sign Sparkle's nested helpers before the enclosing framework and application.
find "$app/Contents/Frameworks" -type f -perm +111 -print0 | while IFS= read -r -d '' executable; do
  if file "$executable" | grep -q 'Mach-O'; then codesign "${flags[@]}" "$executable"; fi
done
find "$app/Contents/Frameworks" -depth \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) -print0 | while IFS= read -r -d '' bundle; do
  codesign "${flags[@]}" "$bundle"
done
codesign "${flags[@]}" "$app"
codesign --verify --deep --strict "$app"
rm -rf 'dist/Agent Burn.app'
mv "$app" 'dist/Agent Burn.app'
echo "Built $PWD/dist/Agent Burn.app ($version)"

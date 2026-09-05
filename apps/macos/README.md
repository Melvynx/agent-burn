# Agent Burn for macOS

Native SwiftUI dashboard and menu-bar app, backed by the Rust Agent Burn CLI.
macOS 14 or newer. Public releases contain Apple Silicon and Intel binaries.

## Install

[Download Agent Burn](https://agent-burn.melvynx.dev/download), unzip it, move
Agent Burn.app to Applications, and open it. No Node.js installation is needed.
Use Settings to configure sources, inspect the metrics backup, and manage update
checks. The app menu also provides **Check for Updates…**.

## Build and test

From this directory:

```sh
./build.sh
open 'dist/Agent Burn.app'
swift test --disable-keychain --disable-xctest
```

Xcode 16 or newer and Rust are required. The repository Nix dev shell provides
CLI tooling; Xcode provides Apple SDKs. `just macos::build` and
`just macos::test` are equivalent root tasks. Swift dependencies are pinned in
Package.resolved. The default build is ad-hoc signed for local development.

## Data

Metrics are stored under `~/Library/Application Support/Agent Burn/`.
`metrics-history.json` preserves observed daily spend and token high-water marks
without expiration. Its `.bak` is the previous valid copy. No prompts or
conversations are archived. Back up this directory to protect against disk loss.
Old data absent from every source cannot be reconstructed. Model breakdowns
reflect available source data, rather than invented historical precision.

The app does not send usage to an Agent Burn service. Live CLI mode can contact
provider endpoints and pricing sources. Sparkle contacts the public update feed
and GitHub release assets. System profile submission is disabled.

## Open release process

1. Increase `Config/version` using `major.minor.patch`. Never reuse a version.
2. Test, commit and push the exact source to a branch on your release repository.
3. Install both Rust targets with `rustup target add aarch64-apple-darwin x86_64-apple-darwin`.
4. Set `AGENT_BURN_SIGN_IDENTITY` to your Developer ID Application certificate.
5. Set `AGENT_BURN_SPARKLE_KEY_FILE` to a private base64 Ed25519 seed file.
6. Set `AGENT_BURN_NOTARY_PROFILE` to a `notarytool` credential profile, or
   authenticate the open-source `asc` CLI for notarization.
7. Run `./release.sh` on the signing Mac.

The script builds from `git archive HEAD`, makes universal binaries, signs the
nested Sparkle helpers and app, notarizes, staples, verifies Gatekeeper, signs
the update archive, and publishes checksums plus a versioned GitHub release.
`macos` is a stable discovery channel independent of the npm CLI releases.
Its appcast always points at immutable `macos-v*` versioned archives.
The website's `/download` and `/appcast.xml` redirects follow that channel.

Private keys and certificates never belong in the repository. Back up the
Sparkle seed securely: losing it prevents signing updates trusted by existing
installations. `Config/sparkle-public-key` is intentionally public. Forks must
create their own key and change the bundle identifier, feed URL, repository,
and site URLs before distributing. Do not reuse this project's update identity.

Sparkle is BSD licensed; its license ships in the application. Agent Burn is
MIT licensed. Provider logos belong to their respective owners and identify
supported integrations; no endorsement is implied.

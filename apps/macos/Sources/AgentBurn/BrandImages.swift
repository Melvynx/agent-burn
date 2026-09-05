import AppKit

@MainActor enum BrandImages {
  // Cursor, Claude and ChatGPT: icons exported from their installed macOS apps.
  // Other icons: first-party favicons from opencode.ai, openclaw.ai, factory.ai,
  // pi.dev, gemini.google.com (gstatic), kimi.com, ampcode.com and qwen.ai (alicdn).
  static let images: [String: NSImage] = {
    let bundle =
      Bundle.main.url(forResource: "AgentBurn_AgentBurn", withExtension: "bundle")
      .flatMap { Bundle(url: $0) } ?? Bundle.module
    return Dictionary(
      uniqueKeysWithValues: [
        "cursor", "claude", "codex", "opencode", "openclaw", "droid", "pi", "gemini", "kimi", "amp",
        "qwen",
      ].compactMap { name in
        guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Brands"),
          let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = false
        return (name, image)
      })
  }()
}

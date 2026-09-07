import AppKit

enum AppLogo {
  static let menuBar: NSImage = {
    let resources =
      Bundle.main.url(forResource: "AgentBurn_AgentBurn", withExtension: "bundle")
      .flatMap { Bundle(url: $0) } ?? Bundle.module
    let image = NSImage(
      contentsOf: resources.url(forResource: "MenuBarIcon", withExtension: "pdf")!)!
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    return image
  }()

  static let window: NSImage = {
    if let icns = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap({
      NSImage(contentsOf: $0)
    }) {
      icns.isTemplate = false
      return icns
    }
    return menuBar
  }()
}

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

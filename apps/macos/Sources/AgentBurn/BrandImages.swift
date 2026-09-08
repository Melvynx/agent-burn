import AppKit

@MainActor enum AppLogo {
  static let menuBar: NSImage = {
    let image = window.copy() as! NSImage
    image.size = NSSize(width: 18, height: 18)
    return image
  }()

  static let window: NSImage = {
    let resources =
      Bundle.main.url(forResource: "AgentBurn_AgentBurn", withExtension: "bundle")
      .flatMap { Bundle(url: $0) } ?? Bundle.module
    let image = NSImage(
      contentsOf: resources.url(forResource: "AppIcon", withExtension: "icns")!)!
    image.isTemplate = false
    return image
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

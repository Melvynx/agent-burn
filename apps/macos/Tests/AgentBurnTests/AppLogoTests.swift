import AppKit
import Testing

@testable import AgentBurn

@Test @MainActor func applicationLogoKeepsFullResolutionAndColorOutsideAppBundle() throws {
  let image = AppLogo.window
  #expect(!image.isTemplate)
  #expect(image.size.width >= 512)
  let data = try #require(image.tiffRepresentation)
  let bitmap = try #require(NSBitmapImageRep(data: data))
  let center = try #require(
    bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
  #expect(center.redComponent > center.greenComponent * 1.3)
  #expect(center.redComponent > center.blueComponent * 2)
}

@Test @MainActor func menuBarKeepsOfficialLogoColorWithoutResizingApplicationLogo() {
  #expect(!AppLogo.menuBar.isTemplate)
  #expect(AppLogo.menuBar.size == NSSize(width: 18, height: 18))
  #expect(AppLogo.menuBar !== AppLogo.window)
  #expect(AppLogo.window.size.width >= 512)
}

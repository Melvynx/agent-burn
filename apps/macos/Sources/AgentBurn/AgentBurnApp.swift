import SwiftUI

@main
struct AgentBurnApp: App {
  @State private var store: UsageStore
  private static let menuIcon: NSImage = {
    let resources =
      Bundle.main.url(forResource: "AgentBurn_AgentBurn", withExtension: "bundle")
      .flatMap { Bundle(url: $0) } ?? Bundle.module
    let image = NSImage(
      contentsOf: resources.url(forResource: "MenuBarIcon", withExtension: "pdf")!)!
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    return image
  }()

  init() {
    let store = UsageStore()
    _store = State(initialValue: store)
    Task { await store.start() }
  }
  var body: some Scene {
    Window("Agent Burn", id: "overview") {
      DashboardView().environment(store)
    }
    .defaultSize(width: 1060, height: 780)
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unified)
    .commands { UpdateCommands() }
    MenuBarExtra {
      MenuPopover().environment(store)
    } label: {
      HStack(spacing: 4) {
        Image(nsImage: Self.menuIcon)
        Text(store.forecast(for: "codex").map { "\(Int($0.remaining))%" } ?? "Burn")
          .monospacedDigit()
      }.accessibilityLabel("Agent Burn usage")
    }
    .menuBarExtraStyle(.window)
    Settings { SettingsView().environment(store) }
  }
}

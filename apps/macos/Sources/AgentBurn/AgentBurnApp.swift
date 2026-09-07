import SwiftUI

@main
struct AgentBurnApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var store: UsageStore

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
      MenuBarLabel(remaining: store.remainingPercent)
        .id(store.remainingPercent ?? -1)
    }
    .menuBarExtraStyle(.window)
    Settings { SettingsView().environment(store) }
  }
}

struct MenuBarLabel: View {
  let remaining: Double?
  var body: some View {
    HStack(spacing: 4) {
      Image(nsImage: AppLogo.menuBar)
        .resizable()
        .renderingMode(.template)
        .frame(width: 18, height: 18)
      Text(menuBarQuotaText(remaining)).monospacedDigit()
    }
    .accessibilityLabel("Agent Burn \(menuBarQuotaText(remaining))")
  }
}

import AppKit
import Observation
import SwiftUI

@Observable @MainActor final class AppAppearance {
  static let shared = AppAppearance()
  private let defaults: UserDefaults
  private let applyPolicy: (NSApplication.ActivationPolicy) -> Void

  var menuBarOnly: Bool {
    didSet {
      defaults.set(menuBarOnly, forKey: "menuBarOnly")
      apply()
    }
  }

  init(
    defaults: UserDefaults = .standard,
    applyPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = {
      NSApplication.shared.setActivationPolicy($0)
    }
  ) {
    self.defaults = defaults
    self.applyPolicy = applyPolicy
    menuBarOnly = defaults.bool(forKey: "menuBarOnly")
  }

  func apply() { applyPolicy(menuBarOnly ? .accessory : .regular) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    AppAppearance.shared.apply()
    if AppAppearance.shared.menuBarOnly {
      // SwiftUI has finished creating its initial dashboard at this point.
      for window in NSApplication.shared.windows where window.title == "Agent Burn" {
        window.orderOut(nil)
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct AppearanceSettings: View {
  @Bindable private var appearance = AppAppearance.shared
  var body: some View {
    Section("Appearance") {
      Toggle("Menu bar only", isOn: $appearance.menuBarOnly)
      Text(
        "Hide Agent Burn from the Dock and Command-Tab. Open the dashboard and Settings from the menu bar. This choice is remembered when the app restarts."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}

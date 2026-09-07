import AppKit
import Observation
import ServiceManagement
import SwiftUI

@Observable @MainActor final class LoginItem {
  private let readStatus: () -> SMAppService.Status
  private let register: () throws -> Void
  private let unregister: () async throws -> Void
  private(set) var status: SMAppService.Status
  private(set) var isUpdating = false
  private(set) var errorMessage: String?

  var isEnabled: Bool { status == .enabled || status == .requiresApproval }
  var requiresApproval: Bool { status == .requiresApproval }

  init(
    readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
    register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
    unregister: @escaping () async throws -> Void = { try await SMAppService.mainApp.unregister() }
  ) {
    self.readStatus = readStatus
    self.register = register
    self.unregister = unregister
    status = readStatus()
  }

  func refresh() { status = readStatus() }

  func setEnabled(_ enabled: Bool) async {
    guard !isUpdating else { return }
    isUpdating = true
    errorMessage = nil
    defer {
      refresh()
      isUpdating = false
    }
    do {
      if enabled { try register() } else { try await unregister() }
    } catch {
      errorMessage = "Could not change login behavior: \(error.localizedDescription)"
    }
  }
}

struct LoginItemSettings: View {
  @State private var loginItem = LoginItem()

  var body: some View {
    Section("Startup") {
      Toggle(
        "Launch at login",
        isOn: Binding(
          get: { loginItem.isEnabled },
          set: { enabled in Task { await loginItem.setEnabled(enabled) } })
      )
      .disabled(loginItem.isUpdating)
      Text(
        "Start Agent Burn automatically when you sign in to your Mac. Your menu-bar-only preference is respected."
      )
      .font(.caption).foregroundStyle(.secondary)
      if loginItem.requiresApproval {
        Text("Allow Agent Burn in System Settings to finish enabling launch at login.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Open Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
      }
      if let error = loginItem.errorMessage {
        Text(error).font(.caption).foregroundStyle(.red)
      }
    }
    .onAppear { loginItem.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      loginItem.refresh()
    }
  }
}

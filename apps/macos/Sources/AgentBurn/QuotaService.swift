import ServiceManagement
import SwiftUI

enum QuotaService {
  static let plistName = "dev.melvynx.agent-burn.quota.plist"
  static var service: SMAppService { .agent(plistName: plistName) }

  static func registerIfNeeded() throws {
    if service.status == .notRegistered || service.status == .notFound {
      try service.register()
    }
  }
}

struct QuotaCollectionSettings: View {
  @AppStorage("backgroundQuotas") private var enabled = true
  @State private var item = LoginItem(
    readStatus: { QuotaService.service.status },
    register: { try QuotaService.service.register() },
    unregister: { try await QuotaService.service.unregister() })

  var body: some View {
    Section("Background quota history") {
      Toggle(
        "Collect quotas every minute",
        isOn: Binding(
          get: { item.isEnabled },
          set: { value in
            enabled = value
            Task { await item.setEnabled(value) }
          })
      )
      .disabled(item.isUpdating)
      Text(
        "Records live Codex and Claude quotas even after you quit Agent Burn. Collection resumes when your Mac wakes or you sign in. Saved readings remain available during outages."
      )
      .font(.caption).foregroundStyle(.secondary)
      if item.requiresApproval {
        Text("Allow Agent Burn to run in the background in System Settings to enable collection.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Open Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
      }
      if let error = item.errorMessage {
        Text(error).font(.caption).foregroundStyle(.red)
      }
    }
    .onAppear { item.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      item.refresh()
    }
  }
}

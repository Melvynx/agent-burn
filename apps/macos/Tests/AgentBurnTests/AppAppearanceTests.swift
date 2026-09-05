import AppKit
import Testing

@testable import AgentBurn

@Test @MainActor func menuBarOnlyPersistsAndRestoresDockVisibility() throws {
  let suite = "AgentBurn.appearance.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  var policies: [NSApplication.ActivationPolicy] = []
  let appearance = AppAppearance(defaults: defaults) { policies.append($0) }
  appearance.apply()
  #expect(policies == [.regular])
  appearance.menuBarOnly = true
  #expect(policies.last == .accessory)
  let reopened = AppAppearance(defaults: defaults) { policies.append($0) }
  #expect(reopened.menuBarOnly)
  reopened.apply()
  #expect(policies.last == .accessory)
  reopened.menuBarOnly = false
  #expect(policies.last == .regular)
  #expect(!AppAppearance(defaults: defaults, applyPolicy: { _ in }).menuBarOnly)
}

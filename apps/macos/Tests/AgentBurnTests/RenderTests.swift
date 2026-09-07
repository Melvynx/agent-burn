import SwiftUI
import Testing

@testable import AgentBurn

// Opt-in visual verification with reports exported by the real CLI.
@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_BURN_RENDER_DIR"] != nil))
@MainActor func renderLiveReports() throws {
  let environment = ProcessInfo.processInfo.environment
  let output = URL(fileURLWithPath: try #require(environment["AGENT_BURN_RENDER_DIR"]))
  let input = URL(fileURLWithPath: try #require(environment["AGENT_BURN_REPORT_DIR"]))
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  let suite = "AgentBurn.render.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let store = UsageStore(
    defaults: defaults, period: .all, storageDirectory: output.appendingPathComponent("storage"))
  store.summary = try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(contentsOf: input.appendingPathComponent("agent-burn-summary.json")))
  store.reports["codex"] = try JSONDecoder().decode(
    HarnessReport.self,
    from: Data(contentsOf: input.appendingPathComponent("agent-burn-codex.json")))
  store.reports["claude"] = try JSONDecoder().decode(
    HarnessReport.self,
    from: Data(contentsOf: input.appendingPathComponent("agent-burn-claude.json")))
  store.updated["claude"] = .now
  store.updated["codex"] = .now
  store.updated["summary"] = .now
  try render(
    SettingsView().environment(store), size: NSSize(width: 560, height: 520),
    to: output.appendingPathComponent("settings.png"))
  store.selection = "summary"
  try render(
    DashboardView().environment(store).frame(width: 1060, height: 780),
    to: output.appendingPathComponent("overview.png"))
  try render(
    MenuPopover().environment(store), size: NSSize(width: 440, height: 780),
    to: output.appendingPathComponent("menu-bar.png"))
  store.selection = "claude"
  try render(
    DashboardView().environment(store).frame(width: 1060, height: 780),
    to: output.appendingPathComponent("claude.png"))
  store.selection = "opencode"
  try render(
    DashboardView().environment(store).frame(width: 1060, height: 780),
    to: output.appendingPathComponent("opencode.png"))
  store.selection = "cursor"
  try render(
    DashboardView().environment(store).frame(width: 1060, height: 780),
    to: output.appendingPathComponent("cursor.png"))
  store.selection = "codex"
  try render(
    DashboardView().environment(store).frame(width: 1060, height: 780),
    to: output.appendingPathComponent("harness.png"))
}

@MainActor private func render(
  _ view: some View, size: NSSize = NSSize(width: 1060, height: 780), to url: URL
) throws {
  _ = NSApplication.shared
  let host = NSHostingView(rootView: view)
  host.frame = NSRect(origin: .zero, size: size)
  let window = NSWindow(
    contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
  window.contentView = host
  host.layoutSubtreeIfNeeded()
  RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  let data = try #require(bitmap.representation(using: .png, properties: [:]))
  try data.write(to: url)
  #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
}

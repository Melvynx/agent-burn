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
  if let directory = environment["AGENT_BURN_QUOTA_HISTORY_DIR"] {
    let source = URL(fileURLWithPath: directory)
    let config = try JSONDecoder().decode(
      QuotaCollectorConfig.self,
      from: Data(contentsOf: source.appendingPathComponent("quota-collector.json")))
    var history = try #require(try QuotaHistoryFile(directory: source).load())
    // Keep the real measurements while rendering with a deliberately disabled CLI.
    history.readings["/nonexistent/render-only-cli|/render"] = history.readings[config.source]
    history.failures["/nonexistent/render-only-cli|/render"] = history.failures[config.source]
    try QuotaHistoryFile(directory: output.appendingPathComponent("storage"))
      .save(history)
  }
  defaults.set("/nonexistent/render-only-cli", forKey: "cliPath")
  defaults.set("/render", forKey: "codexHomes")
  defaults.set(true, forKey: "offline")
  let summary = try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(contentsOf: input.appendingPathComponent("agent-burn-summary.json")))
  let codex = try JSONDecoder().decode(
    HarnessReport.self,
    from: Data(contentsOf: input.appendingPathComponent("agent-burn-codex.json")))
  let claude = try JSONDecoder().decode(
    HarnessReport.self,
    from: Data(contentsOf: input.appendingPathComponent("agent-burn-claude.json")))
  let storage = output.appendingPathComponent("storage")
  try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
  let cache = ReportCache(
    source: "/nonexistent/render-only-cli|/render|true",
    summaries: ["all": CachedReport(report: summary, date: .now)],
    harnesses: [
      "codex": CachedReport(report: codex, date: .now),
      "claude": CachedReport(report: claude, date: .now),
    ])
  try JSONEncoder().encode(cache).write(to: storage.appendingPathComponent("report-cache.json"))
  let store = UsageStore(defaults: defaults, period: .all, storageDirectory: storage)
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
  store.quotaChartRange = .month
  try render(
    DashboardView().environment(store).frame(width: 1060, height: 780),
    to: output.appendingPathComponent("harness-month.png"))
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

// Deterministic visual fixtures; no provider calls or personal usage files.
@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_BURN_COMPACT_RENDER_DIR"] != nil))
@MainActor func renderCompactQuotaStates() throws {
  let output = URL(
    fileURLWithPath: try #require(
      ProcessInfo.processInfo.environment["AGENT_BURN_COMPACT_RENDER_DIR"]))
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  let suite = "AgentBurn.compact.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defaults.set("/usr/bin/false", forKey: "cliPath")
  defer { defaults.removePersistentDomain(forName: suite) }
  let storage = output.appendingPathComponent(UUID().uuidString)
  let store = UsageStore(defaults: defaults, storageDirectory: storage)
  store.selection = "codex"
  let now = Date.now.addingTimeInterval(-30)
  let start = now.addingTimeInterval(-86400)
  let source = store.customPath + "|" + store.codexHomes
  var history = QuotaHistory()
  for minute in 0...1440 {
    history.record(
      QuotaReading(
        agent: "codex",
        observedAt: start.addingTimeInterval(Double(minute) * 60)
          .timeIntervalSince1970 * 1000,
        window: QuotaWindow(
          windowMinutes: 10080, usedPercent: Double(minute / 120) * 3.5,
          elapsedPercent: Double(minute) / 10080 * 100, apiEquivalentSpent: 0)),
      source: source)
  }
  let file = QuotaHistoryFile(directory: storage)
  try file.save(history)
  store.reloadQuotas()
  store.reports["codex"] = HarnessReport(
    agent: "codex", plan: "Pro", liveLimits: true, window: nil,
    apiEquivalentPerMonth: 12691.13, daily: [], topModels: [], pricePerMonth: 200,
    economics: nil, estimate: nil, spendMix: nil, weeklyTrend: nil, imageGenerations: nil)
  store.updated["codex"] = now
  for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
    NSApplication.shared.appearance = NSAppearance(named: appearance)
    try render(
      MenuPopover().environment(store), size: NSSize(width: 440, height: 644),
      to: output.appendingPathComponent("quota-\(name).png"))
  }
  NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
  try render(
    CompactHarnessView(agent: "codex").environment(store).padding(20)
      .frame(width: 320, height: 540, alignment: .top).background(BurnTheme.background),
    size: NSSize(width: 320, height: 540), to: output.appendingPathComponent("quota-narrow.png"))
  store.errors["quotaCollector"] = "Unable to refresh. Check your connection and try again."
  try render(
    MenuPopover().environment(store), size: NSSize(width: 440, height: 644),
    to: output.appendingPathComponent("quota-error.png"))
  let empty = UsageStore(
    defaults: defaults, storageDirectory: output.appendingPathComponent(UUID().uuidString))
  try render(
    CompactHarnessView(agent: "codex").environment(empty).padding(20)
      .frame(width: 320, height: 320, alignment: .top).background(BurnTheme.background),
    size: NSSize(width: 320, height: 320), to: output.appendingPathComponent("quota-empty.png"))
}

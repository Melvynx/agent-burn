import Foundation
import Testing

@testable import AgentBurn

// The fixture deliberately blocks the first CLI read until the test releases it.
@MainActor private struct PeriodFixture {
  let folder: URL
  let defaults: UserDefaults
  let suite: String

  init() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    suite = "AgentBurn.period.\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: suite))
    let executable = folder.appendingPathComponent("fixture")
    let today = UsagePeriod.today.dateBounds(now: .now).1
    try Data(
      """
      #!/bin/sh
      cd "$(dirname "$0")" || exit 1
      printf '%s\\n' "$*" >> calls
      for attempt in $(seq 1 500); do
        [ -f ready ] && break
        sleep 0.01
      done
      [ -f ready ] || exit 1
      [ -f fail ] && exit 9
      [ "$1" = summary ] || exit 2
      printf '%s' '{"totals":{"totalCost":10,"totalTokens":100},"agents":[{"agent":"codex","totalCost":10,"totalTokens":100,"daily":[{"date":"\(today)","cost":10,"tokens":100}],"models":[{"model":"'"$2"'","totalCost":10,"totalTokens":100}]}],"models":[]}'
      """.utf8
    ).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    defaults.set(executable.path, forKey: "cliPath")
    defaults.set("/fixture", forKey: "codexHomes")
    defaults.set(true, forKey: "offline")
    var archive = MetricsArchive()
    archive.agents["codex"] = [today: DailyUsage(date: today, cost: 10, tokens: 100)]
    try MetricsArchiveFile(url: folder.appendingPathComponent("metrics-history.json")).save(archive)
  }

  func release() throws { try Data().write(to: folder.appendingPathComponent("ready")) }
  func calls() -> [String] {
    ((try? String(contentsOf: folder.appendingPathComponent("calls"), encoding: .utf8)) ?? "")
      .split(separator: "\n").map(String.init)
  }
  func cleanUp() {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: folder)
  }
}

@MainActor private func eventually(_ predicate: () -> Bool) async throws {
  for _ in 0..<1000 {
    if predicate() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(predicate(), "Background loading did not reach the expected state")
}

@Test @MainActor func rapidChangesLoadOnlyTheLatestPeriodAndSelectedHarness() async throws {
  let fixture = try PeriodFixture()
  defer { fixture.cleanUp() }
  try fixture.release()
  let store = UsageStore(defaults: fixture.defaults, period: .all, storageDirectory: fixture.folder)
  store.selection = "codex"
  store.period = .week
  store.period = .month
  store.period = .today
  #expect(store.summary?.totals.totalCost == 10)
  try await eventually { !fixture.calls().isEmpty && !store.isLoading }
  #expect(fixture.calls() == ["summary today --value --agents codex --json --no-color --offline"])
}

@Test @MainActor func changingPeriodDuringSlowReadKeepsLatestSelectionAndReusesCache() async throws
{
  let fixture = try PeriodFixture()
  defer { fixture.cleanUp() }
  let store = UsageStore(
    defaults: fixture.defaults, period: .week, storageDirectory: fixture.folder)
  store.selection = "codex"
  try await eventually { fixture.calls().count == 1 }
  #expect(store.isLoading)
  store.period = .month
  store.period = .today
  #expect(store.period == .today)
  #expect(store.summary?.totals.totalCost == 10)
  try fixture.release()
  try await eventually { fixture.calls().count >= 2 && !store.isLoading }
  #expect(fixture.calls().count == 2)
  #expect(fixture.calls().last?.hasPrefix("summary today ") == true)
  #expect(store.summary?.agents.first?.models?.first?.model == "today")
  store.period = .week
  #expect(store.summary?.agents.first?.models?.first?.model == "week")
  store.period = .today
  #expect(store.summary?.agents.first?.models?.first?.model == "today")
  try await Task.sleep(for: .milliseconds(400))
  #expect(fixture.calls().count == 2)
}

@Test @MainActor func periodChangesShowArchivedDataImmediately() throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let suite = "AgentBurn.period.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set("/nonexistent/agent-burn", forKey: "cliPath")
  var archive = MetricsArchive()
  archive.agents["codex"] = [
    UsagePeriod.today.dateBounds(now: .now).1: DailyUsage(
      date: UsagePeriod.today.dateBounds(now: .now).1, cost: 10, tokens: 100),
    "2020-01-01": DailyUsage(date: "2020-01-01", cost: 20, tokens: 200),
  ]
  try MetricsArchiveFile(url: folder.appendingPathComponent("metrics-history.json")).save(archive)
  let store = UsageStore(defaults: defaults, period: .all, storageDirectory: folder)
  #expect(store.summary?.totals.totalCost == 30)
  store.period = .today
  #expect(store.summary?.totals.totalCost == 10)
  store.period = .all
  #expect(store.summary?.totals.totalCost == 30)
}

@Test @MainActor func focusedCacheCannotReplaceAGeneralReport() async throws {
  let fixture = try PeriodFixture()
  defer { fixture.cleanUp() }
  try fixture.release()
  let store = UsageStore(
    defaults: fixture.defaults, period: .today, storageDirectory: fixture.folder)
  store.selection = "codex"
  try await eventually { fixture.calls().count == 1 && !store.isLoading }
  store.selection = "summary"
  try await eventually { fixture.calls().count >= 2 && !store.isLoading }
  #expect(fixture.calls().last == "summary today --value --json --no-color --offline")
  store.selection = "codex"
  try await Task.sleep(for: .milliseconds(400))
  #expect(fixture.calls().count == 2)
}

@Test @MainActor func failedBackgroundReadPreservesDisplayedMetrics() async throws {
  let fixture = try PeriodFixture()
  defer { fixture.cleanUp() }
  try Data().write(to: fixture.folder.appendingPathComponent("fail"))
  try fixture.release()
  let store = UsageStore(
    defaults: fixture.defaults, period: .week, storageDirectory: fixture.folder)
  store.selection = "codex"
  try await eventually { fixture.calls().count == 1 && !store.isLoading }
  #expect(store.summary?.totals.totalCost == 10)
  #expect(store.errors["summary"] != nil)
  store.period = .today
  #expect(store.summary?.totals.totalCost == 10)
  try await eventually { fixture.calls().count >= 2 && !store.isLoading }
  #expect(store.summary?.totals.totalCost == 10)
}

@Test @MainActor func reportsDefaultToAMinuteWithoutOverridingSavedIntervals() throws {
  let fixture = try PeriodFixture()
  defer { fixture.cleanUp() }
  #expect(
    UsageStore(defaults: fixture.defaults, storageDirectory: fixture.folder).refreshMinutes == 1)
  fixture.defaults.set(15, forKey: "refreshMinutes")
  #expect(
    UsageStore(defaults: fixture.defaults, storageDirectory: fixture.folder).refreshMinutes == 15)
}

@Test @MainActor func periodChangesKeepTheLatestCursorAccount() async throws {
  let fixture = try PeriodFixture()
  defer { fixture.cleanUp() }
  try fixture.release()
  fixture.defaults.set("cursor", forKey: "quotaSource")
  let report = try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(
      """
      {"totals":{"totalCost":0,"totalTokens":0},"agents":[],"models":[],"cursorAccount":{"includedPercentUsed":20,"grants":[]}}
      """.utf8))
  let cache = ReportCache(
    source: fixture.folder.appendingPathComponent("fixture").path + "|/fixture|true",
    summaries: ["all": CachedReport(report: report, date: .now)], harnesses: [:])
  try JSONEncoder().encode(cache).write(
    to: fixture.folder.appendingPathComponent("report-cache.json"))
  let store = UsageStore(defaults: fixture.defaults, period: .all, storageDirectory: fixture.folder)
  #expect(store.remainingPercent == 80)
  store.period = .today
  #expect(store.remainingPercent == 80)
  try await eventually { !fixture.calls().isEmpty && !store.isLoading }
  #expect(store.remainingPercent == 80)
}

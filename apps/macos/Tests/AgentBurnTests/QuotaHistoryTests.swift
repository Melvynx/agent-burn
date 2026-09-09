import Foundation
import Testing

@testable import AgentBurn

private func reading(_ percent: Double = 14, date: Date = .now) -> QuotaReading {
  QuotaReading(
    agent: "codex", observedAt: date.timeIntervalSince1970 * 1000,
    window: QuotaWindow(
      windowMinutes: 10080, usedPercent: percent, elapsedPercent: 20, apiEquivalentSpent: 0))
}

private func reading(
  _ percent: Double, elapsed: Double, date: Date, agent: String = "codex"
) -> QuotaReading {
  QuotaReading(
    agent: agent, observedAt: date.timeIntervalSince1970 * 1000,
    window: QuotaWindow(
      windowMinutes: 10080, usedPercent: percent, elapsedPercent: elapsed, apiEquivalentSpent: 0))
}

@Test func quotaHistoryCountsScheduledAndPossibleResets() {
  var history = QuotaHistory()
  let start = Date(timeIntervalSince1970: 1_000_000)
  history.record(reading(90, elapsed: 95, date: start), source: "test")
  history.record(reading(4, elapsed: 2, date: start.addingTimeInterval(60)), source: "test")
  history.record(reading(50, elapsed: 40, date: start.addingTimeInterval(120)), source: "test")
  history.record(reading(8, elapsed: 41, date: start.addingTimeInterval(180)), source: "test")
  let resets = history.resets(agent: "codex", source: "test")
  #expect(resets.map(\.scheduled) == [true, false])
  #expect(resets.count == 2)
}

@Test func quotaHistorySurvivesCollectorFailureAndCorruptPrimary() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = QuotaHistoryFile(directory: directory)
  var history = QuotaHistory()
  history.record(reading(), source: "test")
  try file.save(history)
  history.fail(agent: "codex", source: "test", message: "Network unavailable")
  try file.save(history)
  #expect(try file.load()?.latest(agent: "codex", source: "test")?.window.usedPercent == 14)
  try Data("broken".utf8).write(to: file.url)
  #expect(try file.load()?.latest(agent: "codex", source: "test")?.window.usedPercent == 14)
}

@Test func quotaHistoryRejectsInvalidAndDuplicateMeasurements() {
  var history = QuotaHistory()
  let sample = reading()
  history.record(sample, source: "test")
  history.record(sample, source: "test")
  history.record(reading(-1), source: "test")
  #expect(history.samples(agent: "codex", source: "test").count == 1)
  #expect(history.latest(agent: "codex", source: "other") == nil)
}

@Test @MainActor func quotaGraphLoadsWithoutCLIOrReportCache() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let suite = "quota-test-\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defer {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  defaults.set("/missing/cli", forKey: "cliPath")
  defaults.set("/test/codex", forKey: "codexHomes")
  var history = QuotaHistory()
  history.record(reading(), source: "/missing/cli|/test/codex")
  try QuotaHistoryFile(directory: directory).save(history)
  let store = UsageStore(defaults: defaults, storageDirectory: directory)
  #expect(store.forecast(for: "codex")?.remaining == 86)
  #expect(store.samples(for: "codex").map(\.remaining) == [100, 86])
}

@Test func headlessCollectorPersistsSuccessWhileAnotherProviderFails() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let executable = directory.appendingPathComponent("quota fixture")
  let json = String(decoding: try JSONEncoder().encode(reading()), as: UTF8.self)
  try Data(
    """
    #!/bin/sh
    [ "$AGENT_BURN_QUOTA_ONLY" = 1 ] || exit 3
    [ "$2" = codex ] || exit 4
    printf '%s' '\(json)'
    """.utf8
  ).write(to: executable)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
  let config = QuotaCollectorConfig(customPath: executable.path, codexHomes: "/test")
  try config.save(directory: directory)
  try await QuotaCollector.collect(directory: directory)
  let saved = try #require(try QuotaHistoryFile(directory: directory).load())
  #expect(saved.latest(agent: "codex", source: config.source)?.window.usedPercent == 14)
  #expect(saved.failures[config.source]?["claude"] != nil)
  #expect(saved.samples(agent: "claude", source: config.source).isEmpty)
}

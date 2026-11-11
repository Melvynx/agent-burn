import Foundation
import Testing

@testable import AgentBurn

private func detailedCache(source: String = "test", cost: Double = 12) throws -> ReportCache {
  let report = try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(
      """
      {"totals":{"totalCost":\(cost),"totalTokens":100},"agents":[{"agent":"codex","totalCost":\(cost),"totalTokens":100,"models":[{"model":"gpt-test","totalCost":\(cost),"totalTokens":100}],"daily":[{"date":"2026-01-01","cost":\(cost),"tokens":100}],"tokenBreakdown":{"input":100}}],"models":[{"model":"gpt-test","totalCost":\(cost),"totalTokens":100}]}
      """.utf8))
  return ReportCache(
    source: source,
    summaries: ["all": CachedReport(report: report, date: Date(timeIntervalSince1970: cost))],
    harnesses: [:])
}

@Test func detailedHistoryKeepsEveryChangedVersionAndDeduplicatesIdenticalReports() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let journal = UsageJournal(directory: directory)
  try journal.record(try detailedCache())
  try journal.record(try detailedCache())
  try journal.record(try detailedCache(cost: 20))
  let snapshots = try journal.records()
  #expect(snapshots.count == 2)
  let reports = try snapshots.map { try JSONDecoder().decode(SummaryReport.self, from: $0.payload) }
  #expect(Set(reports.map { $0.totals.totalCost }) == [12, 20])
  #expect(reports.allSatisfy { $0.agents.first?.tokenBreakdown?["input"] == 100 })
}

@Test func detailedCacheRecoversAfterBothWorkingCopiesAreCorrupted() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = ReportCacheFile(directory: directory)
  try file.save(try detailedCache())
  try file.save(try detailedCache(cost: 20))
  try Data("broken".utf8).write(to: file.url)
  try Data("broken".utf8).write(to: file.url.appendingPathExtension("bak"))
  let restored = try #require(try file.load(source: "test"))
  #expect(restored.summaries["all"]?.report.totals.totalCost == 20)
  #expect(restored.summaries["all"]?.report.agents.first?.models?.first?.model == "gpt-test")
}

@Test func changingDataSourcesDoesNotErasePreviousSourceReports() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let file = ReportCacheFile(directory: directory)
  try file.save(try detailedCache(source: "first"))
  try file.save(try detailedCache(source: "second", cost: 20))
  #expect(try file.load(source: "first")?.summaries["all"]?.report.totals.totalCost == 12)
  #expect(try file.load(source: "second")?.summaries["all"]?.report.totals.totalCost == 20)
}

@Test @MainActor func historyRebuildsDailyGraphsAndModelsWithoutWorkingFiles() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let suite = "journal-test-\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defer {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  defaults.set("/missing", forKey: "cliPath")
  defaults.set("/codex", forKey: "codexHomes")
  try UsageJournal(directory: directory).record(try detailedCache(source: "/missing|/codex|false"))
  let store = UsageStore(defaults: defaults, storageDirectory: directory)
  #expect(store.summary?.daily?.first?.date == "2026-01-01")
  #expect(store.summary?.agents.first?.models?.first?.model == "gpt-test")
  #expect(store.summary?.totals.totalCost == 12)
}

@Test func journalAppendsLinesInsteadOfRewritingHistory() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let journal = UsageJournal(directory: directory)
  try journal.record(try detailedCache())
  let url = directory.appendingPathComponent("usage-journal.jsonl")
  let first = try Data(contentsOf: url)
  try journal.record(try detailedCache(cost: 20))
  let second = try Data(contentsOf: url)
  #expect(second.prefix(first.count) == first)
  #expect(second.split(separator: UInt8(ascii: "\n")).count == 2)
}

@Test func legacyJournalMigratesOnceToJSONLines() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let legacy = directory.appendingPathComponent("usage-journal.json")
  let snapshot = UsageSnapshot(date: .distantPast, source: "old", payload: Data("{}".utf8))
  try JSONEncoder().encode([snapshot]).write(to: legacy)
  let journal = UsageJournal(directory: directory)
  try journal.record(try detailedCache())
  #expect(!FileManager.default.fileExists(atPath: legacy.path))
  #expect(try journal.records().map(\.source) == ["old", "test"])
}

@Test func partialTrailingLineDoesNotCorruptTheNextRecord() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let journal = UsageJournal(directory: directory)
  try journal.record(try detailedCache())
  let handle = try FileHandle(forWritingTo: directory.appendingPathComponent("usage-journal.jsonl"))
  try handle.seekToEnd()
  try handle.write(contentsOf: Data("{\"date\":1,\"sou".utf8))
  try handle.close()
  try journal.record(try detailedCache(cost: 20))
  let costs = try journal.records().map {
    try JSONDecoder().decode(SummaryReport.self, from: $0.payload).totals.totalCost
  }
  #expect(costs == [12, 20])
}

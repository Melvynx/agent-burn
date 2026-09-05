import Foundation
import Testing

@testable import AgentBurn

private func snapshot(_ days: String) throws -> SummaryReport {
  try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(
      """
      {"totals":{"totalCost":0,"totalTokens":0},"agents":[{"agent":"cursor","totalCost":0,"totalTokens":0,"daily":[\(days)]}],"models":[]}
      """.utf8))
}

@Test func archivePreservesDeletedDaysWithoutAddingDuplicateSnapshots() throws {
  var archive = MetricsArchive()
  let full = try snapshot(
    """
    {"date":"2026-08-31","cost":20,"tokens":200},{"date":"2026-09-01","cost":10,"tokens":100}
    """)
  archive.ingest(full)
  archive.ingest(full)
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":15,"tokens":150}
      """))
  let report = archive.report(period: .all, live: nil)
  #expect(report.totals.totalCost == 35)
  #expect(report.totals.totalTokens == 350)
  #expect(report.daily?.count == 2)
}

@Test func archiveDoesNotLoseMetricsWhenSourceReturnsPartialDay() throws {
  var archive = MetricsArchive()
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":20,"tokens":200}
      """))
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":5,"tokens":50}
      """))
  #expect(archive.report(period: .all, live: nil).totals.totalCost == 20)
}

@Test func archiveFiltersCalendarMonthAndSurvivesDiskRoundTrip() throws {
  var archive = MetricsArchive()
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-08-31","cost":20,"tokens":200},{"date":"2026-09-01","cost":10,"tokens":100}
      """))
  let restored = try JSONDecoder().decode(MetricsArchive.self, from: JSONEncoder().encode(archive))
  let now = try Date("2026-09-05T12:00:00Z", strategy: .iso8601)
  #expect(restored.report(period: .mtd, live: nil, now: now).totals.totalCost == 10)
  #expect(restored.report(period: .all, live: nil, now: now).totals.totalCost == 30)
}

@Test func archiveRecoversPreviousFileWhenPrimaryIsCorrupted() throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let file = MetricsArchiveFile(url: folder.appendingPathComponent("metrics.json"))
  var archive = MetricsArchive()
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":20,"tokens":200}
      """))
  try file.save(archive)
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-02","cost":5,"tokens":50}
      """))
  try file.save(archive)
  try Data("broken".utf8).write(to: file.url)
  let restored = try file.load()
  #expect(restored?.report(period: .all, live: nil).totals.totalCost == 20)
}

@Test @MainActor func storeShowsArchivedMetricsWithoutAnySourceReports() throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  var archive = MetricsArchive()
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-08-31","cost":20,"tokens":200}
      """))
  try MetricsArchiveFile(url: folder.appendingPathComponent("metrics-history.json")).save(archive)
  let suite = "AgentBurn.archive.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let store = UsageStore(defaults: defaults, period: .all, storageDirectory: folder)
  #expect(store.summary?.totals.totalCost == 20)
  #expect(store.summary?.totals.totalTokens == 200)
  #expect(store.knownAgents == ["cursor"])
}

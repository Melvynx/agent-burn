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

@Test func allTimeSnapshotReplacesReportedDay() throws {
  var archive = MetricsArchive()
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":20,"tokens":200}
      """), policy: .replaceReportedDays)
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":5,"tokens":50}
      """), policy: .replaceReportedDays)
  #expect(archive.report(period: .all, live: nil).totals.totalCost == 5)
  #expect(archive.report(period: .all, live: nil).totals.totalTokens == 50)
}

@Test func filteredSnapshotDoesNotInflateExistingDay() throws {
  var archive = MetricsArchive()
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":10,"tokens":100}
      """), policy: .replaceReportedDays)
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":20,"tokens":100}
      """), policy: .fillMissingDays)
  #expect(archive.report(period: .all, live: nil).totals.totalCost == 10)
  #expect(archive.report(period: .all, live: nil).totals.totalTokens == 100)
}

@Test func filteredSnapshotFillsMissingDayOnly() throws {
  var archive = MetricsArchive()
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":10,"tokens":100}
      """), policy: .replaceReportedDays)
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-08-31","cost":8,"tokens":80}
      """), policy: .fillMissingDays)
  #expect(archive.report(period: .all, live: nil).totals.totalCost == 18)
}

@Test func archivePreservesCursorModelDailySpend() throws {
  var archive = MetricsArchive()
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":10,"tokens":100,"cursorModelsCost":3,"cursorModelsTokens":30}
      """))
  let day = archive.report(period: .all, live: nil).daily?.first
  #expect(day?.cursorModelsCost == 3)
  #expect(day?.cursorModelsTokens == 30)
}

@Test func laterAllTimeSnapshotKeepsDaysItNoLongerReports() throws {
  var archive = MetricsArchive()
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-08-31","cost":20,"tokens":200},{"date":"2026-09-01","cost":10,"tokens":100}
      """), policy: .replaceReportedDays)
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-09-01","cost":9,"tokens":90}
      """), policy: .replaceReportedDays)
  let report = archive.report(period: .all, live: nil)
  #expect(report.totals.totalCost == 29)
  #expect(report.daily?.map(\.date) == ["2026-08-31", "2026-09-01"])
}

@Test func metricsIngestPolicyTreatsOnlyAllAsReplace() {
  #expect(metricsIngestPolicy(for: "all") == .replaceReportedDays)
  #expect(metricsIngestPolicy(for: "all:codex") == .replaceReportedDays)
  #expect(metricsIngestPolicy(for: "today") == .fillMissingDays)
  #expect(metricsIngestPolicy(for: "today:codex") == .fillMissingDays)
  #expect(metricsIngestPolicy(for: "month") == .fillMissingDays)
}

@Test func metricsIngestOrderAppliesNewestAllLast() {
  let items = [
    ("all:cursor", Date(timeIntervalSince1970: 1)),
    ("all", Date(timeIntervalSince1970: 3)),
    ("today:codex", Date(timeIntervalSince1970: 4)),
    ("all:codex", Date(timeIntervalSince1970: 2)),
  ]
  #expect(
    items.sorted(by: metricsIngestOrder).map(\.0)
      == ["all:cursor", "all:codex", "all", "today:codex"])
}

@Test func newestAllSnapshotWinsOverStaleAgentAll() throws {
  var archive = MetricsArchive()
  let stale = try snapshot(
    """
    {"date":"2026-09-09","cost":100,"tokens":100}
    """)
  let latest = try snapshot(
    """
    {"date":"2026-09-09","cost":531,"tokens":500}
    """)
  let items: [(String, Date, SummaryReport)] = [
    ("all:cursor", Date(timeIntervalSince1970: 1), stale),
    ("all", Date(timeIntervalSince1970: 3), latest),
    ("today:codex", Date(timeIntervalSince1970: 4), stale),
  ]
  for (key, _, report) in items.sorted(by: { metricsIngestOrder(($0.0, $0.1), ($1.0, $1.1)) }) {
    archive.ingest(report, policy: metricsIngestPolicy(for: key))
  }
  #expect(archive.report(period: .all, live: nil).totals.totalCost == 531)
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

@Test func archiveFiltersResetToDateFromLastReset() throws {
  var archive = MetricsArchive()
  archive.ingest(
    try snapshot(
      """
      {"date":"2026-08-31","cost":20,"tokens":200},{"date":"2026-09-01","cost":10,"tokens":100}
      """))
  let now = try Date("2026-09-05T12:00:00Z", strategy: .iso8601)
  let reset = try Date("2026-09-01T00:00:00Z", strategy: .iso8601)
  #expect(
    archive.report(period: .rtd, live: nil, now: now, resetStart: reset).totals.totalCost == 10)
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

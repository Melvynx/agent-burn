import Foundation
import Testing

@testable import AgentBurn

@Test func includesStandardCodexLogsAlongsideHarnessSpecificHome() {
  #expect(
    SourcePaths.codexHomes(home: "/Users/test", inherited: "/Users/test/.codex-video")
      == "/Users/test/.codex,/Users/test/.codex-video")
}

@Test func avoidsCountingTheSameCodexHomeTwice() {
  #expect(
    SourcePaths.codexHomes(
      home: "/Users/test", inherited: "/Users/test/.codex/, /Users/test/.codex")
      == "/Users/test/.codex")
}

@Test func allTimeDoesNotPassAnUnsupportedRangeToCLI() {
  #expect(UsagePeriod.all.arguments == ["summary", "--value"])
  #expect(UsagePeriod.mtd.arguments == ["summary", "mtd", "--value"])
}

@Test func reportCachePreservesHistoricalDailyUsage() throws {
  let report = try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(
      """
      {"totals":{"totalCost":1234,"totalTokens":1000},"agents":[],"models":[],"daily":[{"date":"2025-01-01","cost":1234}]}
      """.utf8))
  let cache = ReportCache(
    source: "source",
    summaries: ["all": CachedReport(report: report, date: Date(timeIntervalSince1970: 10))],
    harnesses: [:])
  let restored = try JSONDecoder().decode(ReportCache.self, from: JSONEncoder().encode(cache))
  #expect(restored.summaries["all"]?.report.daily?.first?.date == "2025-01-01")
  #expect(restored.summaries["all"]?.report.totals.totalCost == 1234)
}

@Test func retainsHarnessNavigationAcrossCachedDateRanges() throws {
  let old = try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(
      """
      {"totals":{"totalCost":10,"totalTokens":100},"agents":[{"agent":"opencode","totalCost":10,"totalTokens":100}],"models":[]}
      """.utf8))
  let recent = try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(
      """
      {"totals":{"totalCost":0,"totalTokens":0},"agents":[],"models":[]}
      """.utf8))
  let cache = ReportCache(
    source: "source",
    summaries: [
      "all": CachedReport(report: old, date: .now),
      "today": CachedReport(report: recent, date: .now),
    ], harnesses: [:])
  #expect(cache.agentNames == ["opencode"])
}

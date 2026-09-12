import Foundation
import Testing

@testable import AgentBurn

@Test func claudeAccountSurvivesArchivalProjection() throws {
  let report = try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(
      """
      {"totals":{"totalCost":0,"totalTokens":0},"agents":[],"models":[],"claudeAccount":{"sessionUsedPercent":18,"weeklyUsedPercent":9,"weeklyResetsAtMs":1790000000000,"scoped":[{"name":"Fable","usedPercent":15}],"extraEnabled":true,"extraUsedUSD":25,"extraLimitUSD":1000,"extraUsedPercent":2.5}}
      """.utf8))
  let projected = MetricsArchive().report(period: .all, live: report)
  #expect(projected.claudeAccount?.sessionUsedPercent == 18)
  #expect(projected.claudeAccount?.weeklyUsedPercent == 9)
  #expect(projected.claudeAccount?.scoped.first?.name == "Fable")
  #expect(projected.claudeAccount?.extraUsedUSD == 25)
}

@Test func claudeRemainingUsesWeeklyMeterWhenForecastIsMissing() throws {
  let account = try JSONDecoder().decode(
    ClaudeAccount.self,
    from: Data(#"{"weeklyUsedPercent":12,"scoped":[]}"#.utf8))
  #expect(
    remainingQuota(for: .claude, forecast: nil, cursorAccount: nil, claudeAccount: account) == 88)
}

@Test func extraUsagePercentFallsBackToUsedOverLimit() {
  let account = ClaudeAccount(extraUsedUSD: 25, extraLimitUSD: 1000)
  #expect(extraUsedPercent(account) == 2.5)
}

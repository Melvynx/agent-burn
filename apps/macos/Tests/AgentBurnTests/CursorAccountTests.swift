import Foundation
import Testing

@testable import AgentBurn

@Test func cursorPromotionalCreditsIgnoreExhaustedAndMissingGrants() throws {
  let empty = try JSONDecoder().decode(
    CursorAccount.self, from: Data(#"{"includedPercentUsed":20,"grants":[]}"#.utf8))
  let spent = try JSONDecoder().decode(
    CursorAccount.self,
    from: Data(
      #"{"activePercentUsed":100,"grants":[{"kind":"promo","totalUSD":100,"remainingUSD":0}]}"#
        .utf8))
  let active = try JSONDecoder().decode(
    CursorAccount.self,
    from: Data(
      #"{"activePercentUsed":40,"grants":[{"kind":"promo","totalUSD":100,"remainingUSD":60}]}"#
        .utf8))
  #expect(!cursorHasPromotionalCredits(empty))
  #expect(!cursorHasPromotionalCredits(spent))
  #expect(cursorHasPromotionalCredits(active))
}

@Test func cursorQuotaReadingTracksPromoRemainingUntilExpiry() throws {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let expires = now.addingTimeInterval(365 * 86_400)
  let account = try JSONDecoder().decode(
    CursorAccount.self,
    from: Data(
      """
      {"activePercentUsed":39.5,"activeRemainingUSD":5993.88,"activeLimitUSD":9900.27,\
      "billingCycleStartMs":\(now.addingTimeInterval(-16 * 86_400).timeIntervalSince1970 * 1000),\
      "grants":[{"kind":"promo","totalUSD":9900.27,"remainingUSD":5993.88,\
      "expiresAtMs":\(expires.timeIntervalSince1970 * 1000)}]}
      """.utf8))
  let reading = try #require(cursorQuotaReading(account, now: now))
  #expect(reading.agent == "cursor")
  #expect(reading.window.usedPercent == 39.5)
  #expect(reading.window.isValid)
  #expect(abs(reading.window.windowMinutes - 365 * 1_440) < 2)
  #expect(reading.window.elapsedPercent < 1)
}

@Test func cursorQuotaReadingAcceptsLiveCachedPromoGrant() throws {
  let now = Date(timeIntervalSince1970: 1_789_179_646)
  let account = try JSONDecoder().decode(
    CursorAccount.self,
    from: Data(
      """
      {"activePercentUsed":33.87227203296831,"activeRemainingUSD":6550.13,\
      "activeLimitUSD":9905.27,"billingCycleEndMs":1790483947000,\
      "grants":[{"kind":"promo","totalUSD":9905.27,"remainingUSD":6550.13,\
      "expiresAtMs":1819945202627}]}
      """.utf8))
  let reading = try #require(cursorQuotaReading(account, now: now))
  #expect(reading.window.isValid)
  #expect(reading.window.usedPercent == 33.87227203296831)
  #expect(cursorMeterForecast(account: account, now: now, stored: nil) != nil)
}

@Test func cursorQuotaReadingSkipsAccountsWithoutPromoCredits() throws {
  let account = try JSONDecoder().decode(
    CursorAccount.self, from: Data(#"{"includedPercentUsed":20,"grants":[]}"#.utf8))
  #expect(cursorQuotaReading(account, now: Date(timeIntervalSince1970: 1_800_000_000)) == nil)
}

@Test func cursorModelScopeFiltersSpendAndModelLists() {
  #expect(isCursorModel("composer-2.5"))
  #expect(isCursorModel("cursor-grok-4.6-high-fast"))
  #expect(isCursorModel("auto"))
  #expect(!isCursorModel("claude-4.6-opus"))
  #expect(!isCursorModel("gpt-5.4"))
  let days = [
    DailyUsage(
      date: "2026-09-01", cost: 10, tokens: 100, cursorModelsCost: 3, cursorModelsTokens: 30),
    DailyUsage(date: "2026-09-02", cost: 8, tokens: 80),
  ]
  let cursorDays = dailyUsage(days, scope: .cursorModels)
  #expect(cursorDays.map(\.cost) == [3, 0])
  #expect(dailyUsage(days, scope: .allModels).map(\.cost) == [10, 8])
  let models = [
    ModelUsage(model: "composer-2.5", totalCost: 3, totalTokens: 30),
    ModelUsage(model: "claude-4.6-opus", totalCost: 7, totalTokens: 70),
  ]
  #expect(modelUsage(models, scope: .cursorModels).map(\.model) == ["composer-2.5"])
  #expect(modelUsage(models, scope: .allModels).count == 2)
}

@Test func cursorAccountSurvivesArchivalProjection() throws {
  let report = try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(
      """
      {"totals":{"totalCost":0,"totalTokens":0},"agents":[],"models":[],"cursorAccount":{"includedLimitUSD":400,"includedRemainingUSD":400,"includedPercentUsed":0,"activeRemainingUSD":9130.20,"activeLimitUSD":9905.27,"activePercentUsed":7.83,"billingCycleEndMs":1790483947000,"grants":[{"kind":"promo","totalUSD":9905.27,"remainingUSD":9130.20,"expiresAtMs":1819945202627}]}}
      """.utf8))
  let projected = MetricsArchive().report(period: .all, live: report)
  #expect(projected.cursorAccount?.includedLimitUSD == 400)
  #expect(projected.cursorAccount?.activePercentUsed == 7.83)
  #expect(projected.cursorAccount?.grants.first?.remainingUSD == 9130.20)
  #expect(projected.cursorAccount?.onDemandLimitUSD == nil)
}

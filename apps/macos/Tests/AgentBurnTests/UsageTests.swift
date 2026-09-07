import Foundation
import Testing

@testable import AgentBurn

@Test func forecastUsesElapsedCycleAndRemainingQuota() throws {
  let window = try JSONDecoder().decode(
    QuotaWindow.self,
    from: Data(
      """
      {"windowMinutes":10080,"usedPercent":40,"elapsedPercent":25,"apiEquivalentSpent":120}
      """.utf8))
  let forecast = Forecast(window: window, observedAt: Date(timeIntervalSince1970: 0))
  #expect(forecast.remaining == 60)
  #expect(forecast.projectedUse == 160)
  #expect(abs(forecast.daysEarly - 2.625) < 0.001)
  #expect(abs(forecast.dailyAllowance - 11.42857) < 0.001)
}

@Test func missingLimitsRemainUnavailable() throws {
  let report = try JSONDecoder().decode(
    HarnessReport.self,
    from: Data(
      """
      {"agent":"claude","plan":null,"liveLimits":false,"window":null,
       "apiEquivalentPerMonth":0,"daily":[],"topModels":[]}
      """.utf8))
  #expect(report.window == nil)
  #expect(report.plan == nil)
}

@Test func emptyCycleHasNoExhaustionPrediction() {
  let window = QuotaWindow(
    windowMinutes: 10080, usedPercent: 0, elapsedPercent: 0, apiEquivalentSpent: 0)
  let forecast = Forecast(window: window, observedAt: .now)
  #expect(forecast.projectedUse == nil)
  #expect(forecast.daysEarly == 0)
  #expect(forecast.dailyAllowance.isFinite)
}

@Test func historyDoesNotMixQuotaCycles() {
  let now = Date(timeIntervalSince1970: 1_000_000)
  let points = [
    QuotaSample(date: now.addingTimeInterval(-800_000), remaining: 12),
    QuotaSample(date: now.addingTimeInterval(-200), remaining: 72),
    QuotaSample(date: now.addingTimeInterval(-100), remaining: 74),
    QuotaSample(date: now, remaining: 70),
  ]
  let current = cycleSamples(points, since: now.addingTimeInterval(-1000))
  #expect(current.map(\.remaining) == [74, 70])
}

@Test func cursorRemainingUsesIncludedAllowance() throws {
  let account = try JSONDecoder().decode(
    CursorAccount.self,
    from: Data(#"{"includedPercentUsed":85,"grants":[]}"#.utf8))
  #expect(remainingQuota(for: .cursor, forecast: nil, cursorAccount: account) == 15)
}

@Test func menuBarShowsIntegerRemainingPercent() {
  #expect(menuBarQuotaText(15.9) == "15%")
  #expect(menuBarQuotaText(nil) == "Burn")
}

@Test @MainActor func remainingPercentFollowsLiveCodexWindow() throws {
  let suite = "AgentBurn.quota.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  let store = UsageStore(defaults: defaults, period: .all, storageDirectory: directory)
  store.reports["codex"] = try JSONDecoder().decode(
    HarnessReport.self,
    from: Data(
      """
      {"agent":"codex","plan":"Pro","liveLimits":true,
       "window":{"windowMinutes":10080,"usedPercent":90,"elapsedPercent":50,"apiEquivalentSpent":1},
       "apiEquivalentPerMonth":0,"daily":[],"topModels":[]}
      """.utf8))
  store.updated["codex"] = Date()
  #expect(store.remainingPercent == 10)
}

@Test @MainActor func quotaSourcePersistsAcrossRelaunch() throws {
  let suite = "AgentBurn.quota.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let store = UsageStore(defaults: defaults, period: .all)
  #expect(store.quotaSource == .codex)
  store.quotaSource = .claude
  #expect(UsageStore(defaults: defaults, period: .all).quotaSource == .claude)
}

@Test func menuBarLogoIsAvailableImmediately() {
  #expect(AppLogo.menuBar.size.width > 0)
  #expect(AppLogo.menuBar.size.height > 0)
}

@Test func decodesCompleteHarnessEconomicsAndTrends() throws {
  let report = try JSONDecoder().decode(
    HarnessReport.self,
    from: Data(
      """
      {"agent":"codex","plan":"Pro","liveLimits":true,"window":null,
      "pricePerMonth":200,"apiEquivalentPerMonth":600,"daily":[],"topModels":[],
      "economics":{"pricePerMonth":200,"apiEquivalentPerMonth":600,"subsidyPerMonth":400,"valueMultiple":3,"discountPercent":66.67},
      "weeklyTrend":[{"weekStart":"2026-08-31","cost":100}],
      "spendMix":[{"key":"input","label":"input","tokens":100,"tokenPercent":100,"costUSD":5,"costPercent":100}],
      "imageGenerations":{"count":2,"pricePerImageEstimate":0.15,"estimatedCost":0.3}}
      """.utf8))
  #expect(report.economics?.valueMultiple == 3)
  #expect(report.weeklyTrend?.first?.cost == 100)
  #expect(report.spendMix?.first?.costUSD == 5)
  #expect(report.imageGenerations?.count == 2)
}

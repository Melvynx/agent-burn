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

@Test func resetSummaryCountsScheduledAndPossibleResets() {
  #expect(resetSummary([]) == "No quota resets recorded")
  #expect(
    resetSummary([
      QuotaReset(date: Date(timeIntervalSince1970: 1), scheduled: true),
      QuotaReset(date: Date(timeIntervalSince1970: 2), scheduled: false),
    ]) == "2 recorded · 1 scheduled, 1 possible")
}

@Test func quotaResetCountsSplitScheduledAndPossible() {
  let counts = quotaResetCounts([
    QuotaReset(date: Date(timeIntervalSince1970: 1), scheduled: true),
    QuotaReset(date: Date(timeIntervalSince1970: 2), scheduled: false),
    QuotaReset(date: Date(timeIntervalSince1970: 3), scheduled: false),
  ])
  #expect(counts == QuotaResetCounts(recorded: 3, scheduled: 1))
  #expect(counts.possible == 2)
  #expect(quotaResetDetail(counts) == "1 scheduled · 2 possible")
}

@Test func quotaResetDetailHandlesEmptyHistory() {
  #expect(quotaResetCounts([]) == QuotaResetCounts(recorded: 0, scheduled: 0))
  #expect(quotaResetDetail(quotaResetCounts([])) == "None this cycle")
}

@Test func quotaResetDetailOmitsTheZeroSide() {
  #expect(quotaResetDetail(QuotaResetCounts(recorded: 2, scheduled: 0)) == "2 possible")
  #expect(quotaResetDetail(QuotaResetCounts(recorded: 2, scheduled: 2)) == "2 scheduled")
}

@Test func quotaDateCompactJoinsDayAndTimeWithoutAt() {
  let date = Date(timeIntervalSince1970: 1_704_067_500)
  #expect(quotaDateCompact(date) == "\(quotaDayLabel(date)) · \(quotaTimeLabel(date))")
  #expect(!quotaDateCompact(date).contains(" at "))
}

@Test func quotaAvailableResetsLabelNamesTheCount() {
  #expect(quotaAvailableResetsLabel(nil) == nil)
  #expect(quotaAvailableResetsLabel(0) == "0 resets available")
  #expect(quotaAvailableResetsLabel(1) == "1 reset available")
  #expect(quotaAvailableResetsLabel(2) == "2 resets available")
}

@Test func quotaCompactStatsOmitsInferredHistory() {
  let window = QuotaWindow(
    windowMinutes: 10080, usedPercent: 13, elapsedPercent: 30, apiEquivalentSpent: 0)
  let forecast = Forecast(window: window, observedAt: .now)
  let daily =
    "\(forecast.dailyAllowance.formatted(.number.precision(.fractionLength(1))))%\u{00A0}/ day"
  #expect(quotaCompactStats(forecast) == "13.0% used · \(daily)")
  #expect(
    quotaCompactStats(forecast, availableResets: 1) == "13.0% used · \(daily) · 1 reset available")
}

@Test func quotaBlendRatesCrossSpendPercentAndTokens() {
  let rates = quotaBlendRates(usedPercent: 15, spent: 30, tokens: 1_500_000)
  #expect(rates.dollarsPerPercent == 2)
  #expect(rates.tokensPerDollar == 50_000)
  #expect(rates.tokensPerPercent == 100_000)
}

@Test func quotaBlendRatesNeedPositiveInputs() {
  #expect(quotaBlendRates(usedPercent: 0, spent: 10, tokens: 100).dollarsPerPercent == nil)
  #expect(quotaBlendRates(usedPercent: 10, spent: 0, tokens: 100).tokensPerDollar == nil)
  #expect(quotaBlendRates(usedPercent: 10, spent: 5, tokens: 0).tokensPerPercent == nil)
}

@Test func quotaCycleSpendPrefersWindowThenDaily() {
  let days = [
    DailyUsage(date: "2026-09-08", cost: 4, tokens: 40_000),
    DailyUsage(date: "2026-09-10", cost: 6, tokens: 60_000),
  ]
  #expect(quotaCycleSpend(windowSpent: 12, days: days, since: "2026-09-10") == 12)
  #expect(quotaCycleSpend(windowSpent: 0, days: days, since: "2026-09-10") == 6)
  #expect(quotaCycleTokens(days: days, since: "2026-09-10") == 60_000)
}

@Test func quotaBlendLabelsFormatUnitRates() {
  #expect(quotaDollarsPerPercentLabel(2.137) == "\(currency(2.137)) / %")
  #expect(quotaTokensPerUnitLabel(142_350, unit: "$") == "\(tokens(142_350)) / $")
  #expect(quotaDollarsPerPercentLabel(nil) == nil)
  #expect(quotaTokensPerUnitLabel(nil, unit: "$") == nil)
}

@Test func quotaBlendUsesWindowSpendAndModelTokens() throws {
  let report = try JSONDecoder().decode(
    HarnessReport.self,
    from: Data(
      """
      {"agent":"codex","liveLimits":true,
       "window":{"windowMinutes":10080,"usedPercent":10,"elapsedPercent":20,"apiEquivalentSpent":20},
       "apiEquivalentPerMonth":100,"daily":[],
       "topModels":[{"model":"gpt","cost":100,"tokens":5000000}]}
      """.utf8))
  let forecast = Forecast(
    window: report.window!, observedAt: Date(timeIntervalSince1970: 1_700_000_000))
  let rates = quotaBlendRates(forecast: forecast, report: report)
  #expect(rates.dollarsPerPercent == 2)
  #expect(rates.tokensPerDollar == 50_000)
  #expect(rates.tokensPerPercent == nil)
}

@Test func quotaUsedPercentClampsWindowUse() {
  let window = QuotaWindow(
    windowMinutes: 10080, usedPercent: 140, elapsedPercent: 50, apiEquivalentSpent: 0)
  #expect(quotaUsedPercent(Forecast(window: window, observedAt: .now)) == 100)
}

@Test func cursorRemainingUsesIncludedAllowance() throws {
  let account = try JSONDecoder().decode(
    CursorAccount.self,
    from: Data(#"{"includedPercentUsed":85,"grants":[]}"#.utf8))
  #expect(remainingQuota(for: .cursor, forecast: nil, cursorAccount: account) == 15)
}

@Test func cursorRemainingPrefersActiveCredits() throws {
  let account = try JSONDecoder().decode(
    CursorAccount.self,
    from: Data(
      #"""
      {"includedPercentUsed":0,"activePercentUsed":25,"grants":[{"kind":"promo","totalUSD":10000,"remainingUSD":7500}]}
      """#.utf8))
  #expect(remainingQuota(for: .cursor, forecast: nil, cursorAccount: account) == 75)
}

@Test func cursorRemainingPrefersLiveForecastWhenPresent() throws {
  let account = try JSONDecoder().decode(
    CursorAccount.self,
    from: Data(#"{"activePercentUsed":25,"grants":[{"kind":"promo","remainingUSD":75}]}"#.utf8))
  let forecast = Forecast(
    window: QuotaWindow(
      windowMinutes: 365 * 1_440, usedPercent: 40, elapsedPercent: 10, apiEquivalentSpent: 0),
    observedAt: .now, isLive: true)
  #expect(remainingQuota(for: .cursor, forecast: forecast, cursorAccount: account) == 60)
}

@Test func menuBarShowsIntegerRemainingPercent() {
  #expect(menuBarQuotaText(15.9) == "15%")
  #expect(menuBarQuotaText(nil) == "Burn")
}

@Test func appVersionTextIncludesShortVersionAndBuild() {
  #expect(appVersionText(short: "0.1.1", build: "1451") == "v0.1.1 (1451)")
}

@Test func appVersionTextOmitsEmptyBuild() {
  #expect(appVersionText(short: "0.1.1", build: "") == "v0.1.1")
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

@Test @MainActor func menuBarLogoIsAvailableImmediately() {
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
      "imageGenerations":{"count":2,"pricePerImageEstimate":0.15,"estimatedCost":0.3},
      "resetCreditsAvailable":2}
      """.utf8))
  #expect(report.resetCreditsAvailable == 2)
  #expect(report.economics?.valueMultiple == 3)
  #expect(report.weeklyTrend?.first?.cost == 100)
  #expect(report.spendMix?.first?.costUSD == 5)
  #expect(report.imageGenerations?.count == 2)
}

@Test func activityChartDomainUsesTheSelectedPeriodForEveryHarness() {
  let now = usageDayDate("2026-09-12")!
  let domain = activityChartDomain(
    period: .month, knownDates: ["2026-06-22", "2026-09-10"], now: now)
  #expect(domain?.lowerBound == usageDayDate("2026-08-14"))
  #expect(domain?.upperBound == now)
}

@Test func activityChartDomainSharesAllTimeAcrossHarnesses() {
  let now = usageDayDate("2026-09-12")!
  let domain = activityChartDomain(
    period: .all, knownDates: ["2026-06-22", "2025-09-01"], now: now)
  #expect(domain?.lowerBound == usageDayDate("2025-09-01"))
  #expect(domain?.upperBound == now)
}

@Test func activityChartDomainIsNilWithoutDatesOnAllTime() {
  #expect(
    activityChartDomain(period: .all, knownDates: [], now: usageDayDate("2026-09-12")!) == nil)
}

private func codexQuotaReading(at date: Date, used: Double, windowStart: Date) -> QuotaReading {
  let minutes = 10080.0
  let elapsed = date.timeIntervalSince(windowStart) / (minutes * 60) * 100
  return QuotaReading(
    agent: "codex", observedAt: date.timeIntervalSince1970 * 1000,
    window: QuotaWindow(
      windowMinutes: minutes, usedPercent: used, elapsedPercent: elapsed,
      apiEquivalentSpent: 0))
}

@Test func quotaHistoryDropsStaleReplayOfASupersededCycle() {
  let start1 = Date(timeIntervalSince1970: 1_780_000_000)
  let tail = start1.addingTimeInterval(90_000)
  let start2 = tail.addingTimeInterval(60)
  var history = QuotaHistory()
  let source = "cli|homes"
  let points = [
    codexQuotaReading(at: start1.addingTimeInterval(86_400), used: 60, windowStart: start1),
    codexQuotaReading(at: tail, used: 69, windowStart: start1),
    codexQuotaReading(at: start2, used: 0, windowStart: start2),
    codexQuotaReading(at: start2.addingTimeInterval(3_600), used: 12, windowStart: start2),
    // Provider hiccup replays the superseded cycle for a few minutes.
    codexQuotaReading(
      at: start2.addingTimeInterval(3_660), used: 71, windowStart: start1),
    codexQuotaReading(
      at: start2.addingTimeInterval(3_720), used: 71, windowStart: start1),
    codexQuotaReading(at: start2.addingTimeInterval(3_780), used: 12, windowStart: start2),
  ]
  for point in points { history.record(point, source: source) }

  #expect(
    history.samples(agent: "codex", source: source).map(\.remaining) == [40, 31, 100, 88, 88])
  #expect(history.latest(agent: "codex", source: source)?.observedAt == points.last?.observedAt)
}

@Test func quotaHistoryKeepsGenuineResetsAcrossCycles() {
  let start1 = Date(timeIntervalSince1970: 1_780_000_000)
  let start2 = start1.addingTimeInterval(604_800)
  var history = QuotaHistory()
  let source = "cli|homes"
  for point in [
    codexQuotaReading(at: start1.addingTimeInterval(500_000), used: 69, windowStart: start1),
    codexQuotaReading(at: start2.addingTimeInterval(60), used: 0, windowStart: start2),
    codexQuotaReading(at: start2.addingTimeInterval(3_600), used: 12, windowStart: start2),
  ] { history.record(point, source: source) }

  #expect(
    history.samples(agent: "codex", source: source).map(\.remaining) == [31, 100, 88])
  let resets = history.resets(agent: "codex", source: source)
  #expect(resets.count == 1)
  #expect(resets.first?.date == start2.addingTimeInterval(60))
}

@Test func quotaHistoryReplayRecoveryIsNotCountedAsAReset() {
  let start1 = Date(timeIntervalSince1970: 1_780_000_000)
  let tail = start1.addingTimeInterval(90_000)
  let start2 = tail.addingTimeInterval(60)
  var history = QuotaHistory()
  let source = "cli|homes"
  for point in [
    codexQuotaReading(at: tail, used: 69, windowStart: start1),
    codexQuotaReading(at: start2, used: 0, windowStart: start2),
    codexQuotaReading(at: start2.addingTimeInterval(3_600), used: 12, windowStart: start2),
    codexQuotaReading(
      at: start2.addingTimeInterval(3_660), used: 71, windowStart: start1),
    codexQuotaReading(at: start2.addingTimeInterval(3_720), used: 12, windowStart: start2),
  ] { history.record(point, source: source) }

  #expect(history.resets(agent: "codex", source: source).count == 1)
}

private func spendTestCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.firstWeekday = 2
  calendar.minimumDaysInFirstWeek = 4
  calendar.locale = Locale(identifier: "en_US_POSIX")
  return calendar
}

@Test func spendGranularityAutoKeepsShortRangesDaily() {
  #expect(spendGranularityAuto(spanDays: 1) == .daily)
  #expect(spendGranularityAuto(spanDays: 62) == .daily)
  #expect(spendGranularityAuto(spanDays: 63) == .weekly)
  #expect(spendGranularityAuto(spanDays: 182) == .weekly)
  #expect(spendGranularityAuto(spanDays: 183) == .monthly)
  #expect(spendGranularityAuto(spanDays: 400) == .monthly)
}

@Test func bucketDailyUsageKeepsDailyOrder() {
  let calendar = spendTestCalendar()
  let days = [
    DailyUsage(date: "2026-09-10", cost: 6, tokens: 60_000),
    DailyUsage(date: "2026-09-08", cost: 4, tokens: 40_000),
  ]
  let bucketed = bucketDailyUsage(days, granularity: .daily, calendar: calendar)
  #expect(bucketed.map(\.date) == ["2026-09-08", "2026-09-10"])
  #expect(bucketed.map(\.cost) == [4, 6])
}

@Test func bucketDailyUsageGroupsTheSameWeek() {
  let calendar = spendTestCalendar()
  // Mon Sep 7 through Sun Sep 13 2026 share one ISO week.
  let days = [
    DailyUsage(date: "2026-09-07", cost: 2, tokens: 10_000),
    DailyUsage(date: "2026-09-09", cost: 3, tokens: 20_000),
    DailyUsage(date: "2026-09-13", cost: 5, tokens: 30_000),
    DailyUsage(date: "2026-09-14", cost: 7, tokens: 40_000),
  ]
  let bucketed = bucketDailyUsage(days, granularity: .weekly, calendar: calendar)
  #expect(bucketed.map(\.date) == ["2026-09-07", "2026-09-14"])
  #expect(bucketed.map(\.cost) == [10, 7])
  #expect(bucketed.first?.tokens == 60_000)
}

@Test func bucketDailyUsageGroupsTheSameMonth() {
  let calendar = spendTestCalendar()
  let days = [
    DailyUsage(date: "2026-08-31", cost: 4),
    DailyUsage(date: "2026-09-01", cost: 6),
    DailyUsage(date: "2026-09-20", cost: 10),
  ]
  let bucketed = bucketDailyUsage(days, granularity: .monthly, calendar: calendar)
  #expect(bucketed.map(\.date) == ["2026-08-01", "2026-09-01"])
  #expect(bucketed.map(\.cost) == [4, 16])
}

@Test func spendBucketStartUsesMondayWeeksAndMonthFirst() {
  let calendar = spendTestCalendar()
  let wednesday = usageDayDate("2026-09-09")!
  #expect(
    quotaDayKey(spendBucketStart(for: wednesday, granularity: .weekly, calendar: calendar))
      == "2026-09-07")
  #expect(
    quotaDayKey(spendBucketStart(for: wednesday, granularity: .monthly, calendar: calendar))
      == "2026-09-01")
  #expect(spendSpanDays(lower: wednesday, upper: wednesday) == 1)
}

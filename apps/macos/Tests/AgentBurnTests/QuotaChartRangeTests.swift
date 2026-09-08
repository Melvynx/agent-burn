import Foundation
import Testing

@testable import AgentBurn

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let window = QuotaWindow(
  windowMinutes: 10080, usedPercent: 40, elapsedPercent: 50, apiEquivalentSpent: 0)
private let forecast = Forecast(window: window, observedAt: now)

private func sample(_ offset: TimeInterval, remaining: Double) -> QuotaSample {
  QuotaSample(date: now.addingTimeInterval(offset), remaining: remaining)
}

@Test func quotaChartUntilResetUsesTheCurrentCycleWindow() {
  let domain = quotaChartWindow(range: .rte, forecast: forecast, now: now)
  #expect(domain.lowerBound == forecast.start)
  #expect(domain.upperBound == forecast.reset)
}

@Test func quotaChartResetToTodayStopsAtTheLatestReading() {
  let domain = quotaChartWindow(range: .rtd, forecast: forecast, now: now)
  #expect(domain.lowerBound == forecast.start)
  #expect(domain.upperBound == now)
}

@Test func quotaChartCalendarRangesCoverTodayWeekAndMonth() {
  #expect(
    quotaChartWindow(range: .today, forecast: forecast, now: now).lowerBound
      == Calendar.current.startOfDay(for: now))
  #expect(
    quotaChartWindow(range: .week, forecast: forecast, now: now).lowerBound
      == now.addingTimeInterval(-7 * 86_400))
  #expect(
    quotaChartWindow(range: .month, forecast: forecast, now: now).lowerBound
      == now.addingTimeInterval(-30 * 86_400))
}

@Test func quotaChartMonthStopsAtLatestReadingNotReset() {
  let domain = quotaChartWindow(range: .month, forecast: forecast, now: now)
  #expect(domain.upperBound == now)
  #expect(domain.upperBound < forecast.reset)
}

@Test func quotaChartMonthUsesObservedAtWhenClockIsLater() {
  let later = now.addingTimeInterval(120 * 86_400)
  let domain = quotaChartWindow(range: .month, forecast: forecast, now: later)
  #expect(domain.upperBound == now)
  #expect(domain.lowerBound == now.addingTimeInterval(-30 * 86_400))
}

@Test func quotaChartUntilResetDropsEarlierCycles() {
  let samples = [
    sample(-800_000, remaining: 12),
    sample(-200, remaining: 72),
    sample(-100, remaining: 70),
    sample(0, remaining: 60),
  ]
  #expect(
    quotaChartSamples(samples, range: .rte, forecast: forecast, now: now).map(\.remaining)
      == [72, 70, 60])
}

@Test func quotaChartMonthKeepsResetsInsideTheWindow() {
  let samples = [
    sample(-20 * 86_400, remaining: 8),
    sample(-19 * 86_400, remaining: 96),
    sample(-100, remaining: 61),
    sample(0, remaining: 60),
  ]
  #expect(
    quotaChartSamples(samples, range: .month, forecast: forecast, now: now).map(\.remaining)
      == [8, 96, 61, 60])
}

@Test @MainActor func quotaChartRangePersistsAndDoesNotChangeSpendPeriod() throws {
  let suite = "AgentBurn.quota-range.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  let store = UsageStore(defaults: defaults, period: .mtd, storageDirectory: directory)
  #expect(store.quotaChartRange == .rte)
  store.quotaChartRange = .month
  #expect(store.period == .mtd)
  #expect(
    UsageStore(defaults: defaults, period: .mtd, storageDirectory: directory).quotaChartRange
      == .month)
}

import Foundation
import Testing

@testable import AgentBurn

@Test func quotaChartDoesNotConnectAcrossMissingMeasurements() {
  let date = Date.now
  let samples = [
    QuotaSample(date: date, remaining: 86),
    QuotaSample(date: date.addingTimeInterval(60), remaining: 85),
    QuotaSample(date: date.addingTimeInterval(3600), remaining: 75),
  ]
  #expect(quotaSampleSegments(samples).map { $0.map(\.remaining) } == [[86, 85], [75]])
}

@Test func menuQuotaMarksStaleValuesWithoutChangingTheirAmount() {
  #expect(menuBarQuotaText(86, stale: true) == "86% · stale")
  #expect(menuBarQuotaText(75, stale: false) == "75%")
  #expect(menuBarQuotaText(nil, stale: true) == "Burn")
}

@Test func liveQuotaBecomesStaleWhenMinuteRefreshStops() {
  let date = Date(timeIntervalSince1970: 1_800_000_000)
  let forecast = Forecast(
    window: QuotaWindow(
      windowMinutes: 10080, usedPercent: 25, elapsedPercent: 20,
      apiEquivalentSpent: 0), observedAt: date, isLive: true)
  #expect(forecast.isFresh(at: date.addingTimeInterval(60)))
  #expect(!forecast.isFresh(at: date.addingTimeInterval(91)))
  #expect(!forecast.isFresh(at: date.addingTimeInterval(-1)))
}

@Test func cachedQuotaIsNeverPresentedAsLive() {
  let date = Date.now
  let forecast = Forecast(
    window: QuotaWindow(
      windowMinutes: 10080, usedPercent: 14, elapsedPercent: 20,
      apiEquivalentSpent: 0), observedAt: date)
  #expect(!forecast.isFresh(at: date))
  #expect(forecast.freshnessLabel(at: date) == "Saved reading")
}

@Test func resetQuotaIsStaleEvenIfRecentlyFetched() {
  let date = Date.now
  let forecast = Forecast(
    window: QuotaWindow(
      windowMinutes: 1, usedPercent: 25, elapsedPercent: 90,
      apiEquivalentSpent: 0), observedAt: date, isLive: true)
  #expect(!forecast.isFresh(at: date.addingTimeInterval(7)))
}

@Test func failedRefreshLabelsTheLastKnownValue() {
  let date = Date.now
  let forecast = Forecast(
    window: QuotaWindow(
      windowMinutes: 10080, usedPercent: 25, elapsedPercent: 20,
      apiEquivalentSpent: 0), observedAt: date, isLive: true)
  #expect(forecast.freshnessLabel(at: date) == "Live · every minute")
  #expect(forecast.freshnessLabel(at: date, failed: true) == "Update failed · retrying")
  #expect(forecast.freshnessLabel(at: date.addingTimeInterval(91)) == "Stale · waiting for update")
}

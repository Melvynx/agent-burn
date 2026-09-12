import Foundation
import SwiftUI
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
      == [100, 72, 70, 60])
}

@Test func quotaChartUntilResetAnchorsRecordedLineAtLimit() {
  let samples = [sample(-200, remaining: 72), sample(0, remaining: 60)]
  let points = quotaChartSamples(samples, range: .rte, forecast: forecast, now: now)
  #expect(points.first == QuotaSample(date: forecast.start, remaining: 100))
  #expect(points.map(\.remaining) == [100, 72, 60])
}

@Test func quotaChartKeepsRealSampleWhenLimitAlreadyRecorded() {
  let samples = [
    QuotaSample(date: forecast.start.addingTimeInterval(30), remaining: 99),
    sample(0, remaining: 60),
  ]
  #expect(
    quotaChartSamples(samples, range: .rte, forecast: forecast, now: now).map(\.remaining)
      == [99, 60])
}

@Test func quotaLimitSummaryLinksUsedPercentToCycleStart() {
  let line = quotaLimitSummary(forecast)
  #expect(line.hasPrefix("Limit: "))
  #expect(line.hasSuffix(" · 40% used"))
  #expect(line.contains(quotaDateText(forecast.start)))
}

private var utc: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return calendar
}

private func utcDate(year: Int = 2027, month: Int = 1, day: Int, hour: Int = 0) -> Date {
  utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@Test func quotaChartUntilResetDrawsALineForEachCalendarDay() {
  #expect(
    quotaChartGridDates(range: .rte, forecast: forecast, now: now, calendar: utc) == [
      utcDate(day: 11), utcDate(day: 12), utcDate(day: 13), utcDate(day: 14), utcDate(day: 15),
      utcDate(day: 16), utcDate(day: 17), utcDate(day: 18),
    ])
}

@Test func quotaChartUntilResetLabelsEachCalendarDay() {
  let grid = quotaChartGridDates(range: .rte, forecast: forecast, now: now, calendar: utc)
  #expect(
    quotaChartAxisDates(range: .rte, forecast: forecast, now: now, calendar: utc)
      == grid.map { utc.date(bySettingHour: 12, minute: 0, second: 0, of: $0)! })
}

@Test func quotaChartDayBandsFillEachCalendarDay() {
  let bands = quotaChartDayBands(range: .rte, forecast: forecast, now: now, calendar: utc)
  let scale = quotaChartScale(range: .rte, forecast: forecast, now: now, calendar: utc)
  #expect(
    bands.map(\.start) == [
      utcDate(day: 11), utcDate(day: 12), utcDate(day: 13), utcDate(day: 14), utcDate(day: 15),
      utcDate(day: 16), utcDate(day: 17), utcDate(day: 18),
    ])
  #expect(
    bands.map(\.end) == [
      utcDate(day: 12), utcDate(day: 13), utcDate(day: 14), utcDate(day: 15), utcDate(day: 16),
      utcDate(day: 17), utcDate(day: 18), scale.upperBound,
    ])
  #expect(bands[4].isCurrent)
}

@Test func quotaChartReadingInterpolatesRecordedAndProjectsTheRest() {
  let samples = [sample(-100, remaining: 80), sample(0, remaining: 60)]
  let mid = quotaChartReading(
    at: now.addingTimeInterval(-50), samples: samples, forecast: forecast, range: .rte)
  #expect(mid.recorded == 70)
  #expect(mid.forecast == nil)
  let latest = quotaChartReading(at: now, samples: samples, forecast: forecast, range: .rte)
  #expect(latest.recorded == 60)
  #expect(latest.ideal == 50)
  let end = quotaChartReading(at: forecast.reset, samples: samples, forecast: forecast, range: .rte)
  #expect(end.recorded == 60)
  #expect(end.ideal == 0)
  #expect(end.forecast == 20)
}

@Test func quotaChartWeekDrawsALineForEachCalendarDay() {
  #expect(
    quotaChartGridDates(range: .week, forecast: forecast, now: now, calendar: utc) == [
      utcDate(day: 8), utcDate(day: 9), utcDate(day: 10), utcDate(day: 11), utcDate(day: 12),
      utcDate(day: 13), utcDate(day: 14), utcDate(day: 15),
    ])
}

@Test func quotaChartTodayDrawsAnHourlyLine() {
  #expect(
    quotaChartGridDates(range: .today, forecast: forecast, now: now, calendar: utc)
      == (0...8).map { utcDate(day: 15, hour: $0) })
}

@Test func quotaChartTodayLabelsEveryThirdHour() {
  #expect(
    quotaChartAxisDates(range: .today, forecast: forecast, now: now, calendar: utc) == [
      utcDate(day: 15), utcDate(day: 15, hour: 3), utcDate(day: 15, hour: 6),
      utcDate(day: 15, hour: 8),
    ])
}

@Test func quotaChartMonthDrawsALineForEachCalendarDay() {
  let dates = quotaChartGridDates(range: .month, forecast: forecast, now: now, calendar: utc)
  #expect(dates.count == 31)
  #expect(dates.first == utcDate(year: 2026, month: 12, day: 16))
  #expect(dates.last == utcDate(day: 15))
}

@Test func quotaChartScaleStartsOnTheFirstDayLine() {
  let scale = quotaChartScale(range: .rte, forecast: forecast, now: now, calendar: utc)
  #expect(scale.lowerBound == utcDate(day: 11))
  #expect(scale.upperBound == utcDate(day: 18, hour: 21))
  #expect(scale.upperBound >= forecast.reset)
}

@Test func quotaChartScaleKeepsRoomAfterTheLastDayLine() throws {
  let late = Forecast(
    window: QuotaWindow(
      windowMinutes: 10080, usedPercent: 40, elapsedPercent: 90, apiEquivalentSpent: 0),
    observedAt: now)
  let last = try #require(
    quotaChartGridDates(range: .rte, forecast: late, now: now, calendar: utc).last)
  let scale = quotaChartScale(range: .rte, forecast: late, now: now, calendar: utc)
  #expect(scale.upperBound.timeIntervalSince(last) >= 14 * 3600)
}

@Test func quotaChartReadingPastLatestIsProjected() {
  let samples = [sample(-100, remaining: 80), sample(0, remaining: 60)]
  let latest = quotaChartReading(at: now, samples: samples, forecast: forecast, range: .rte)
  #expect(!latest.projected)
  #expect(latest.paceDelta == 10)
  let later = quotaChartReading(
    at: forecast.reset, samples: samples, forecast: forecast, range: .rte)
  #expect(later.projected)
  #expect(later.paceDelta == 20)
}

@Test func quotaChartDeltaSegmentsSplitAtPaceCrossing() {
  let quarter = forecast.start.addingTimeInterval(forecast.duration * 0.25)
  let samples = [
    QuotaSample(date: forecast.start, remaining: 100),
    QuotaSample(date: quarter, remaining: 60),
    QuotaSample(date: now, remaining: 60),
  ]
  let segments = quotaChartDeltaSegments(samples: samples, forecast: forecast)
  #expect(segments.map(\.ahead) == [false, true])
  #expect(segments[0].points.map(\.recorded) == [100, 60, 60])
  #expect(segments[0].points.map(\.ideal) == [100, 75, 60])
  #expect(segments[1].points.map(\.recorded) == [60, 60])
  #expect(segments[1].points.map(\.ideal) == [60, 50])
  let crossing = quarter.addingTimeInterval(0.6 * now.timeIntervalSince(quarter))
  #expect(abs(segments[1].points[0].date.timeIntervalSince(crossing)) < 1)
}

@Test func quotaChartDeltaSegmentsMarkADipUnderPaceAsBehind() {
  let quarter = forecast.start.addingTimeInterval(forecast.duration * 0.25)
  let dip = forecast.start.addingTimeInterval(forecast.duration * 0.4)
  let samples = [
    QuotaSample(date: forecast.start, remaining: 100),
    QuotaSample(date: quarter, remaining: 90),
    QuotaSample(date: dip, remaining: 50),
    QuotaSample(date: now, remaining: 70),
  ]
  let segments = quotaChartDeltaSegments(samples: samples, forecast: forecast)
  #expect(segments.map(\.ahead) == [true, false, true])
  #expect(segments[1].points.first?.recorded == segments[1].points.first?.ideal)
  #expect(segments[1].points.last?.recorded == segments[1].points.last?.ideal)
  #expect(segments[1].points.contains { $0.recorded < $0.ideal })
}

@Test func quotaChartRecordedStrokeTurnsRedWhenBehindPace() {
  #expect(quotaChartRecordedStroke(ahead: true, color: .purple) == .purple)
  #expect(quotaChartRecordedStroke(ahead: false, color: .purple) == BurnTheme.behind)
}

@Test func quotaChartSmoothedSamplesCollapsesUnchangedPlateaus() {
  let samples = [
    sample(-400, remaining: 100),
    sample(-300, remaining: 100),
    sample(-200, remaining: 80),
    sample(-100, remaining: 80),
    sample(0, remaining: 80),
  ]
  let smoothed = quotaChartSmoothedSamples(samples)
  #expect(smoothed.map(\.remaining) == [100, 80, 80])
  #expect(smoothed.first?.date == samples.first?.date)
  #expect(smoothed.last?.date == samples.last?.date)
}

@Test func quotaChartSmoothedSamplesTurnsAStraightBurnDownIntoEndpoints() {
  let samples = (0...4).map { step in
    sample(TimeInterval(step - 4) * 100, remaining: 100 - Double(step) * 10)
  }
  #expect(quotaChartSmoothedSamples(samples).map(\.remaining) == [100, 60])
}

@Test func quotaChartSmoothedSamplesKeepsADipOffTheBurnDown() {
  let samples = [
    sample(-200, remaining: 100),
    sample(-100, remaining: 50),
    sample(0, remaining: 60),
  ]
  #expect(quotaChartSmoothedSamples(samples).map(\.remaining) == [100, 50, 60])
}

@Test func quotaChartSmoothedSamplesDropsATinyWiggleOnTheBurnDown() {
  let samples = [
    sample(-400, remaining: 100),
    sample(-300, remaining: 90),
    sample(-200, remaining: 81),
    sample(-100, remaining: 70),
    sample(0, remaining: 60),
  ]
  #expect(quotaChartSmoothedSamples(samples).map(\.remaining) == [100, 60])
}

@Test func quotaChartDeltaTextReportsAheadBehindAndOnPace() {
  #expect(quotaChartDeltaText(12.34) == "+12.3% ahead")
  #expect(quotaChartDeltaText(-8) == "−8.0% behind")
  #expect(quotaChartDeltaText(0.02) == "On pace")
  #expect(quotaChartDeltaText(nil) == nil)
}

@Test func quotaChartStepMovesBetweenDayLines() {
  let marks = (11...18).map { utcDate(day: $0) }
  let domain = utcDate(day: 11)...utcDate(day: 18, hour: 12)
  #expect(
    quotaChartStep(from: utcDate(day: 14, hour: 9), forward: true, marks: marks, domain: domain)
      == utcDate(day: 15))
  #expect(
    quotaChartStep(from: utcDate(day: 14, hour: 9), forward: false, marks: marks, domain: domain)
      == utcDate(day: 14))
  #expect(
    quotaChartStep(from: utcDate(day: 18), forward: true, marks: marks, domain: domain)
      == utcDate(day: 18, hour: 12))
  #expect(
    quotaChartStep(from: utcDate(day: 11), forward: false, marks: marks, domain: domain)
      == utcDate(day: 11))
}

@Test func quotaChartCompactAxisLabelUsesDayNumbersAfterTheFirst() {
  let marks = (8...15).map { utcDate(day: $0) }
  #expect(
    quotaChartAxisLabel(marks[0], range: .rte, marks: marks, compact: true, calendar: utc)
      == marks[0].formatted(.dateTime.month(.abbreviated).day()))
  #expect(
    quotaChartAxisLabel(marks[1], range: .rte, marks: marks, compact: true, calendar: utc)
      == marks[1].formatted(.dateTime.day()))
}

@Test func quotaChartYearWindowKeepsAHandfulOfMonthAxisDates() {
  let long = Forecast(
    window: QuotaWindow(
      windowMinutes: 365 * 1_440, usedPercent: 40, elapsedPercent: 3, apiEquivalentSpent: 0),
    observedAt: now)
  let marks = quotaChartAxisDates(range: .rte, forecast: long, now: now)
  #expect(marks.count <= 6)
  #expect(marks.count >= 2)
  #expect(
    quotaChartAxisLabel(marks[0], range: .rte, marks: marks)
      == marks[0].formatted(.dateTime.month(.abbreviated)))
}

@Test func quotaChartWeekWindowKeepsDailyAxisDates() {
  let marks = quotaChartAxisDates(range: .rte, forecast: forecast, now: now)
  #expect(marks.count >= 6)
  #expect(marks.count <= 9)
}

@Test func quotaChartAxisLabelUsesWeekdayWhenTheWeekFits() {
  let marks = (8...15).map { utcDate(day: $0) }
  #expect(
    quotaChartAxisLabel(marks[1], range: .rte, marks: marks, calendar: utc)
      == marks[1].formatted(.dateTime.weekday(.abbreviated).day()))
}

@Test func quotaChartAxisLabelUsesMonthOnTheFirstMarkAndDayOne() {
  var marks = (16...31).map { utcDate(year: 2026, month: 12, day: $0) }
  marks.append(contentsOf: (1...15).map { utcDate(month: 1, day: $0) })
  #expect(marks.count == 31)
  #expect(
    quotaChartAxisLabel(marks[0], range: .month, marks: marks, calendar: utc)
      == marks[0].formatted(.dateTime.month(.abbreviated).day()))
  #expect(
    quotaChartAxisLabel(marks[1], range: .month, marks: marks, calendar: utc)
      == marks[1].formatted(.dateTime.day()))
  #expect(
    quotaChartAxisLabel(utcDate(month: 1, day: 1), range: .month, marks: marks, calendar: utc)
      == utcDate(month: 1, day: 1).formatted(.dateTime.month(.abbreviated).day()))
}

@Test func quotaRecordedLineConnectsLimitAcrossCollectorGaps() {
  let samples = [
    QuotaSample(date: forecast.start, remaining: 100),
    sample(-20 * 3_600, remaining: 99),
    sample(0, remaining: 60),
  ]
  #expect(
    quotaRecordedSegments(samples, connectGaps: true).map { $0.map(\.remaining) }
      == [[100, 99, 60]])
}

@Test func quotaChartWeekConnectsAcrossCollectorGaps() {
  #expect(QuotaChartRange.week.connectsRecordedGaps)
  let samples = [
    sample(-6 * 86_400, remaining: 40),
    sample(-20 * 3_600, remaining: 30),
    sample(0, remaining: 20),
  ]
  let points = quotaChartSamples(samples, range: .week, forecast: forecast, now: now)
  #expect(points.map(\.remaining) == [40, 30, 20])
  #expect(
    quotaRecordedSegments(points, connectGaps: true).map { $0.map(\.remaining) } == [[40, 30, 20]])
}

@Test func everyQuotaChartRangeConnectsRecordedGaps() {
  #expect(QuotaChartRange.allCases.map(\.connectsRecordedGaps) == [true, true, true, true, true])
}

@Test func quotaChartMonthConnectsAcrossCollectorGaps() {
  let samples = [
    sample(-20 * 86_400, remaining: 8),
    sample(-19 * 86_400, remaining: 96),
    sample(-20 * 3_600, remaining: 30),
    sample(0, remaining: 20),
  ]
  let points = quotaChartSamples(samples, range: .month, forecast: forecast, now: now)
  #expect(points.map(\.remaining) == [8, 96, 30, 20])
  #expect(
    quotaRecordedSegments(points, connectGaps: QuotaChartRange.month.connectsRecordedGaps).map {
      $0.map(\.remaining)
    } == [[8, 96, 30, 20]])
}

@Test func quotaTimeRemainingSitsBetweenResetAndLimit() {
  #expect(quotaTimeRemaining(forecast, now: now) == "3d 12h left")
}

@Test func quotaTimeLeftDropsTheLeftSuffix() {
  #expect(quotaTimeLeft(forecast, now: now) == "3d 12h")
  #expect(quotaTimeLeft(forecast, now: forecast.reset.addingTimeInterval(-2 * 86_400)) == "2d")
  #expect(quotaTimeLeft(forecast, now: forecast.reset.addingTimeInterval(-1800)) == "<1h")
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
  #expect(store.cursorQuotaChartRange == .rtd)
  #expect(store.chartRange(for: "cursor") == .rtd)
  #expect(store.chartRange(for: "codex") == .rte)
  store.quotaChartRange = .month
  store.cursorQuotaChartRange = .week
  #expect(store.period == .mtd)
  let reloaded = UsageStore(defaults: defaults, period: .mtd, storageDirectory: directory)
  #expect(reloaded.quotaChartRange == .month)
  #expect(reloaded.cursorQuotaChartRange == .rtd)
}

import Foundation

struct SummaryReport: Codable, Sendable {
  let totals: Totals
  let agents: [AgentUsage]
  let models: [ModelUsage]
  let daily: [DailyUsage]?
  let subscription: SubscriptionReport?
  var cursorAccount: CursorAccount? = nil
}

struct Totals: Codable, Sendable {
  let totalCost: Double
  let totalTokens: UInt64
}

struct AgentUsage: Codable, Identifiable, Sendable {
  let agent: String
  let totalCost: Double
  let totalTokens: UInt64
  let models: [ModelUsage]?
  let daily: [DailyUsage]?
  let tokenBreakdown: [String: UInt64]?
  var id: String { agent }
}

struct ModelUsage: Codable, Identifiable, Sendable {
  let model: String
  let totalCost: Double
  let totalTokens: UInt64
  var id: String { model }
}

struct HarnessReport: Codable, Sendable {
  let agent: String
  let plan: String?
  let liveLimits: Bool
  let window: QuotaWindow?
  let apiEquivalentPerMonth: Double
  let daily: [DailyUsage]
  let topModels: [HarnessModel]
  let pricePerMonth: Double?
  let economics: Economics?
  let estimate: QuotaEstimate?
  let spendMix: [SpendCategory]?
  let weeklyTrend: [WeeklyUsage]?
  let imageGenerations: ImageUsage?
  var resetCreditsAvailable: Int? = nil
}

struct SubscriptionReport: Codable, Sendable {
  let agents: [SubscriptionAgent]
}

struct SubscriptionAgent: Codable, Identifiable, Sendable {
  let agent: String
  let plan: String?
  let pricePerMonth: Double?
  let periodUsage: Double
  let liveLimits: Bool
  let shortWindow: ShortWindow?
  var resetCreditsAvailable: Int? = nil
  var id: String { agent }
}

struct ShortWindow: Codable, Sendable {
  let label: String
  let usedPercent: Double
}

struct Economics: Codable, Sendable {
  let pricePerMonth: Double
  let apiEquivalentPerMonth: Double
  let subsidyPerMonth: Double
  let valueMultiple: Double
  let discountPercent: Double
}

struct QuotaEstimate: Codable, Sendable {
  let fullQuotaValue: Double
  let monthlyValue: Double
  let projectedUsePercent: Double
  let valueMultiple: Double?
}

struct SpendCategory: Codable, Identifiable, Sendable {
  let key: String
  let label: String
  let tokens: UInt64
  let tokenPercent: Double
  let costUSD: Double
  let costPercent: Double
  var id: String { key }
}

struct WeeklyUsage: Codable, Identifiable, Sendable {
  let weekStart: String
  let cost: Double
  var id: String { weekStart }
}

struct ImageUsage: Codable, Sendable {
  let count: Int
  let pricePerImageEstimate: Double
  let estimatedCost: Double
}

struct QuotaWindow: Codable, Sendable {
  let windowMinutes: Double
  let usedPercent: Double
  let elapsedPercent: Double
  let apiEquivalentSpent: Double

  var isValid: Bool {
    windowMinutes.isFinite && windowMinutes > 0 && usedPercent.isFinite
      && elapsedPercent.isFinite && (0...100).contains(elapsedPercent)
      && (0...100).contains(usedPercent)
  }
}

struct DailyUsage: Codable, Identifiable, Sendable {
  let date: String
  let cost: Double
  var tokens: UInt64? = nil
  var id: String { date }
}

struct HarnessModel: Codable, Identifiable, Sendable {
  let model: String
  let cost: Double
  let tokens: UInt64
  var id: String { model }
}

struct Forecast {
  let window: QuotaWindow
  let observedAt: Date
  var isLive = false
  func isFresh(at date: Date) -> Bool {
    let age = date.timeIntervalSince(observedAt)
    return isLive && window.isValid && age >= 0 && age <= 90 && date < reset
  }
  func freshnessLabel(at date: Date, failed: Bool = false) -> String {
    if failed { return "Update failed · retrying" }
    if !isLive { return "Saved reading" }
    return isFresh(at: date) ? "Live · every minute" : "Stale · waiting for update"
  }
  var remaining: Double { max(0, min(100, 100 - window.usedPercent)) }
  var duration: TimeInterval { max(1, window.windowMinutes * 60) }
  var elapsed: Double { max(0, min(1, window.elapsedPercent / 100)) }
  var start: Date { observedAt.addingTimeInterval(-duration * elapsed) }
  var reset: Date { start.addingTimeInterval(duration) }
  var projectedUse: Double? {
    guard elapsed > 0, window.usedPercent > 0 else { return nil }
    return window.usedPercent / elapsed
  }
  var daysEarly: Double {
    guard let projectedUse, projectedUse > 100 else { return 0 }
    return duration * (1 - 100 / projectedUse) / 86400
  }
  var dailyAllowance: Double {
    remaining / max(1 / 1440, duration * (1 - elapsed) / 86400)
  }
  var projectedEnd: Date {
    guard let projectedUse, projectedUse > 100 else { return reset }
    return start.addingTimeInterval(duration * 100 / projectedUse)
  }
  var projectedRemaining: Double { max(0, 100 - (projectedUse ?? 0)) }
}

struct QuotaSample: Codable, Equatable, Sendable {
  let date: Date
  let remaining: Double
}

enum QuotaChartRange: String, CaseIterable, Identifiable {
  case rte, rtd, today, week, month
  var id: String { rawValue }
  var label: String {
    switch self {
    case .rte: "Until reset"
    case .rtd: "Reset to today"
    case .today: "Today"
    case .week: "Last 7 days"
    case .month: "Last 30 days"
    }
  }
  var connectsRecordedGaps: Bool { true }
}

func quotaChartWindow(
  range: QuotaChartRange, forecast: Forecast, now: Date, calendar: Calendar = .current
) -> ClosedRange<Date> {
  let cursor = min(now, forecast.observedAt)
  let start: Date
  let end: Date
  switch range {
  case .rte:
    start = forecast.start
    end = max(now, forecast.reset)
  case .rtd:
    start = forecast.start
    end = max(cursor, forecast.observedAt)
  case .today:
    start = calendar.startOfDay(for: cursor)
    end = max(cursor, forecast.observedAt)
  case .week:
    start = cursor.addingTimeInterval(-7 * 86_400)
    end = max(cursor, forecast.observedAt)
  case .month:
    start = cursor.addingTimeInterval(-30 * 86_400)
    end = max(cursor, forecast.observedAt)
  }
  return start...max(start.addingTimeInterval(1), end)
}

func quotaChartSamples(
  _ samples: [QuotaSample], range: QuotaChartRange, forecast: Forecast, now: Date
) -> [QuotaSample] {
  let window = quotaChartWindow(range: range, forecast: forecast, now: now)
  let inWindow = samples.filter { $0.date >= window.lowerBound && $0.date <= window.upperBound }
    .sorted { $0.date < $1.date }
  if range == .rte || range == .rtd {
    return quotaChartSamplesFromLimit(
      cycleSamples(inWindow, since: window.lowerBound.addingTimeInterval(-60)),
      forecast: forecast)
  }
  return inWindow
}

func quotaChartSamplesFromLimit(_ samples: [QuotaSample], forecast: Forecast) -> [QuotaSample] {
  let anchor = QuotaSample(date: forecast.start, remaining: 100)
  guard let first = samples.first else { return [anchor] }
  if first.date <= forecast.start.addingTimeInterval(90) { return samples }
  return [anchor] + samples
}

func quotaChartSteppedDates(
  in window: ClosedRange<Date>, component: Calendar.Component, calendar: Calendar
) -> [Date] {
  guard var cursor = calendar.dateInterval(of: component, for: window.lowerBound)?.start else {
    return [window.lowerBound]
  }
  var dates: [Date] = []
  while cursor <= window.upperBound {
    dates.append(cursor)
    guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else {
      break
    }
    cursor = next
  }
  return dates
}

func quotaChartScale(
  range: QuotaChartRange, forecast: Forecast, now: Date, calendar: Calendar = .current
) -> ClosedRange<Date> {
  let window = quotaChartWindow(range: range, forecast: forecast, now: now, calendar: calendar)
  let grid = quotaChartGridDates(range: range, forecast: forecast, now: now, calendar: calendar)
  let start = min(grid.first ?? window.lowerBound, window.lowerBound)
  guard range != .today, let last = grid.last else { return start...window.upperBound }
  // Leave room after the last midday label so it is never clipped at the trailing edge.
  return start...max(window.upperBound, last.addingTimeInterval(21 * 3600))
}

func quotaChartGridDates(
  range: QuotaChartRange, forecast: Forecast, now: Date, calendar: Calendar = .current
) -> [Date] {
  quotaChartSteppedDates(
    in: quotaChartWindow(range: range, forecast: forecast, now: now, calendar: calendar),
    component: range == .today ? .hour : .day,
    calendar: calendar)
}

func quotaChartAxisDates(
  range: QuotaChartRange, forecast: Forecast, now: Date, calendar: Calendar = .current
) -> [Date] {
  let grid = quotaChartGridDates(range: range, forecast: forecast, now: now, calendar: calendar)
  if range == .today {
    return grid.enumerated().compactMap { offset, date in
      offset % 3 == 0 || offset == grid.count - 1 ? date : nil
    }
  }
  let scale = quotaChartScale(range: range, forecast: forecast, now: now, calendar: calendar)
  return grid.map { date in
    let midday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    return min(max(midday, scale.lowerBound), scale.upperBound)
  }
}

func quotaChartDayBands(
  range: QuotaChartRange, forecast: Forecast, now: Date, calendar: Calendar = .current
) -> [QuotaChartBand] {
  guard range != .today else { return [] }
  let grid = quotaChartGridDates(range: range, forecast: forecast, now: now, calendar: calendar)
  let scale = quotaChartScale(range: range, forecast: forecast, now: now, calendar: calendar)
  return grid.enumerated().map { index, start in
    let end = index + 1 < grid.count ? grid[index + 1] : scale.upperBound
    return QuotaChartBand(
      start: start, end: end, isCurrent: calendar.isDate(start, inSameDayAs: now))
  }
}

func quotaChartIdealRemaining(at date: Date, forecast: Forecast) -> Double {
  max(0, min(100, 100 * (1 - date.timeIntervalSince(forecast.start) / forecast.duration)))
}

func quotaChartRecordedRemaining(at date: Date, samples: [QuotaSample]) -> Double? {
  let sorted = samples.sorted { $0.date < $1.date }
  guard let first = sorted.first else { return nil }
  if date <= first.date { return first.remaining }
  if let last = sorted.last, date >= last.date { return last.remaining }
  for (previous, next) in zip(sorted, sorted.dropFirst()) where date <= next.date {
    let span = next.date.timeIntervalSince(previous.date)
    guard span > 0 else { return next.remaining }
    let progress = date.timeIntervalSince(previous.date) / span
    return previous.remaining + (next.remaining - previous.remaining) * progress
  }
  return nil
}

func quotaChartForecastRemaining(at date: Date, forecast: Forecast) -> Double? {
  guard forecast.projectedUse != nil else { return nil }
  if date < forecast.observedAt { return nil }
  if date >= forecast.projectedEnd { return forecast.projectedRemaining }
  let span = forecast.projectedEnd.timeIntervalSince(forecast.observedAt)
  guard span > 0 else { return forecast.projectedRemaining }
  let progress = date.timeIntervalSince(forecast.observedAt) / span
  return forecast.remaining + (forecast.projectedRemaining - forecast.remaining) * progress
}

func quotaChartReading(
  at date: Date, samples: [QuotaSample], forecast: Forecast, range: QuotaChartRange
) -> QuotaChartReading {
  QuotaChartReading(
    date: date,
    recorded: quotaChartRecordedRemaining(at: date, samples: samples),
    ideal: range == .rte || range == .rtd
      ? quotaChartIdealRemaining(at: date, forecast: forecast) : nil,
    forecast: range == .rte ? quotaChartForecastRemaining(at: date, forecast: forecast) : nil,
    projected: date > forecast.observedAt)
}

func quotaChartDeltaSegments(samples: [QuotaSample], forecast: Forecast) -> [QuotaDeltaSegment] {
  let points = quotaChartDeltaPoints(samples: samples, forecast: forecast)
  guard points.count > 1 else { return [] }
  var segments: [QuotaDeltaSegment] = []
  for (previous, next) in zip(points, points.dropFirst()) {
    let ahead = previous.delta + next.delta >= 0
    if var last = segments.last, last.ahead == ahead {
      last.points.append(next)
      segments[segments.count - 1] = last
    } else {
      segments.append(QuotaDeltaSegment(ahead: ahead, points: [previous, next]))
    }
  }
  return segments
}

private func quotaChartDeltaPoints(samples: [QuotaSample], forecast: Forecast)
  -> [QuotaDeltaPoint]
{
  let sorted = samples.sorted { $0.date < $1.date }
  var points: [QuotaDeltaPoint] = []
  for sample in sorted {
    let point = QuotaDeltaPoint(
      date: sample.date, recorded: sample.remaining,
      ideal: quotaChartIdealRemaining(at: sample.date, forecast: forecast))
    if let previous = points.last, previous.delta * point.delta < 0 {
      // Pace is linear and recorded is linear between samples, so the crossing is exact.
      let progress = previous.delta / (previous.delta - point.delta)
      let date = previous.date.addingTimeInterval(
        progress * point.date.timeIntervalSince(previous.date))
      let value = quotaChartIdealRemaining(at: date, forecast: forecast)
      points.append(QuotaDeltaPoint(date: date, recorded: value, ideal: value))
    }
    points.append(point)
  }
  return points
}

func quotaChartDeltaText(_ delta: Double?) -> String? {
  guard let delta else { return nil }
  if abs(delta) < 0.05 { return "On pace" }
  let magnitude = abs(delta).formatted(.number.precision(.fractionLength(1)))
  return delta > 0 ? "+\(magnitude)% ahead" : "−\(magnitude)% behind"
}

func quotaChartStep(from date: Date, forward: Bool, marks: [Date], domain: ClosedRange<Date>)
  -> Date
{
  let sorted = marks.sorted()
  if forward {
    return min(domain.upperBound, sorted.first { $0 > date } ?? domain.upperBound)
  }
  return max(domain.lowerBound, sorted.last { $0 < date } ?? domain.lowerBound)
}

func quotaChartCursorLabel(_ date: Date, range: QuotaChartRange) -> String {
  if range == .today { return date.formatted(.dateTime.hour().minute()) }
  return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
}

func quotaChartPercentLabel(_ value: Double?) -> String {
  value.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—"
}

func quotaChartAxisLabel(
  _ date: Date, range: QuotaChartRange, marks: [Date], compact: Bool = false,
  calendar: Calendar = .current
) -> String {
  if range == .today { return date.formatted(.dateTime.hour()) }
  let short = compact || marks.count > 10
  let isMonthStart = calendar.component(.day, from: date) == 1
  if short {
    if date == marks.first || isMonthStart {
      return date.formatted(.dateTime.month(.abbreviated).day())
    }
    return date.formatted(.dateTime.day())
  }
  return date.formatted(.dateTime.weekday(.abbreviated).day())
}

struct QuotaChartBand: Equatable {
  let start: Date
  let end: Date
  let isCurrent: Bool
}

struct QuotaChartReading: Equatable {
  let date: Date
  let recorded: Double?
  let ideal: Double?
  let forecast: Double?
  let projected: Bool
  var value: Double? { projected ? forecast ?? recorded : recorded }
  var paceDelta: Double? {
    guard let ideal, let value else { return nil }
    return value - ideal
  }
}

struct QuotaDeltaPoint: Equatable {
  let date: Date
  let recorded: Double
  let ideal: Double
  var delta: Double { recorded - ideal }
}

struct QuotaDeltaSegment: Equatable {
  let ahead: Bool
  var points: [QuotaDeltaPoint]
}

func quotaDateText(_ date: Date) -> String {
  date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
}

func quotaDayLabel(_ date: Date) -> String {
  date.formatted(.dateTime.month(.abbreviated).day())
}

func quotaTimeLabel(_ date: Date) -> String {
  date.formatted(.dateTime.hour().minute())
}

func quotaDateCompact(_ date: Date) -> String {
  "\(quotaDayLabel(date)) · \(quotaTimeLabel(date))"
}

func quotaUsedPercent(_ forecast: Forecast) -> Double {
  max(0, min(100, forecast.window.usedPercent))
}

func quotaLimitSummary(_ forecast: Forecast) -> String {
  "Limit: \(quotaDateText(forecast.start)) · \(quotaUsedPercent(forecast).formatted(.number.precision(.fractionLength(0))))% used"
}

func quotaTimeLeft(_ forecast: Forecast, now: Date) -> String {
  let seconds = max(0, forecast.reset.timeIntervalSince(min(now, forecast.reset)))
  let days = Int(seconds / 86_400)
  let hours = Int((seconds - Double(days) * 86_400) / 3_600)
  if days > 0 && hours > 0 { return "\(days)d \(hours)h" }
  if days > 0 { return "\(days)d" }
  if hours > 0 { return "\(hours)h" }
  return "<1h"
}

func quotaTimeRemaining(_ forecast: Forecast, now: Date) -> String {
  let left = quotaTimeLeft(forecast, now: now)
  return left == "<1h" ? "Less than 1h left" : "\(left) left"
}

func quotaChartSmoothedSamples(_ samples: [QuotaSample], epsilon: Double = 1.25) -> [QuotaSample] {
  let points = quotaChartCollapsedSamples(samples)
  guard points.count > 2 else { return points }
  var keep = [Bool](repeating: false, count: points.count)
  keep[0] = true
  keep[points.count - 1] = true
  quotaChartSimplify(points, start: 0, end: points.count - 1, epsilon: epsilon, keep: &keep)
  return zip(points, keep).compactMap { sample, kept in kept ? sample : nil }
}

private func quotaChartCollapsedSamples(_ samples: [QuotaSample]) -> [QuotaSample] {
  let sorted = samples.sorted { $0.date < $1.date }
  guard let first = sorted.first else { return [] }
  var result = [first]
  for sample in sorted.dropFirst() {
    if abs(sample.remaining - result[result.count - 1].remaining) >= 0.05 {
      result.append(sample)
    }
  }
  if let last = sorted.last, result.last != last {
    result.append(last)
  }
  return result
}

private func quotaChartSimplify(
  _ points: [QuotaSample], start: Int, end: Int, epsilon: Double, keep: inout [Bool]
) {
  guard end > start + 1 else { return }
  var maxError = 0.0
  var index = start
  for i in (start + 1)..<end {
    let error = quotaChartLineError(points[i], from: points[start], to: points[end])
    if error > maxError {
      maxError = error
      index = i
    }
  }
  guard maxError > epsilon else { return }
  keep[index] = true
  quotaChartSimplify(points, start: start, end: index, epsilon: epsilon, keep: &keep)
  quotaChartSimplify(points, start: index, end: end, epsilon: epsilon, keep: &keep)
}

private func quotaChartLineError(_ point: QuotaSample, from start: QuotaSample, to end: QuotaSample)
  -> Double
{
  let span = end.date.timeIntervalSince(start.date)
  let progress = span > 0 ? point.date.timeIntervalSince(start.date) / span : 0
  let expected = start.remaining + (end.remaining - start.remaining) * progress
  return abs(point.remaining - expected)
}

func quotaRecordedSegments(_ samples: [QuotaSample], connectGaps: Bool) -> [[QuotaSample]] {
  let sorted = samples.sorted { $0.date < $1.date }
  if connectGaps { return sorted.isEmpty ? [] : [sorted] }
  return quotaSampleSegments(sorted)
}

func quotaSampleSegments(_ samples: [QuotaSample]) -> [[QuotaSample]] {
  var segments: [[QuotaSample]] = []
  for sample in samples.sorted(by: { $0.date < $1.date }) {
    if let previous = segments.last?.last,
      sample.date.timeIntervalSince(previous.date) <= 90
    {
      segments[segments.count - 1].append(sample)
    } else {
      segments.append([sample])
    }
  }
  return segments
}

func cycleSamples(_ samples: [QuotaSample], since start: Date) -> [QuotaSample] {
  let sorted = samples.filter { $0.date >= start }.sorted { $0.date < $1.date }
  var result: [QuotaSample] = []
  for sample in sorted {
    // A quota increase indicates a reset or a provider correction.
    if let previous = result.last, sample.remaining > previous.remaining + 1 {
      result.removeAll()
    }
    result.append(sample)
  }
  return result
}

struct QuotaResetCounts: Equatable {
  let recorded: Int
  let scheduled: Int
  var possible: Int { recorded - scheduled }
}

func quotaResetCounts(_ resets: [QuotaReset]) -> QuotaResetCounts {
  QuotaResetCounts(recorded: resets.count, scheduled: resets.filter(\.scheduled).count)
}

func quotaAvailableResetsLabel(_ count: Int?) -> String? {
  guard let count else { return nil }
  return count == 1 ? "1 reset available" : "\(count) resets available"
}

func quotaCompactStats(_ forecast: Forecast, availableResets: Int? = nil) -> String {
  let used =
    "\(quotaUsedPercent(forecast).formatted(.number.precision(.fractionLength(1))))% used"
  let daily =
    "\(forecast.dailyAllowance.formatted(.number.precision(.fractionLength(1))))%\u{00A0}/ day"
  guard let resets = quotaAvailableResetsLabel(availableResets) else { return "\(used) · \(daily)" }
  return "\(used) · \(daily) · \(resets)"
}

func quotaResetDetail(_ counts: QuotaResetCounts) -> String {
  if counts.recorded == 0 { return "None this cycle" }
  if counts.scheduled == 0 { return "\(counts.possible) possible" }
  if counts.possible == 0 { return "\(counts.scheduled) scheduled" }
  return "\(counts.scheduled) scheduled · \(counts.possible) possible"
}

func resetSummary(_ resets: [QuotaReset]) -> String {
  let counts = quotaResetCounts(resets)
  guard counts.recorded > 0 else { return "No quota resets recorded" }
  return "\(counts.recorded) recorded · \(counts.scheduled) scheduled, \(counts.possible) possible"
}

enum QuotaSource: String, CaseIterable, Identifiable {
  case codex, claude, cursor
  var id: String { rawValue }
  var label: String {
    switch self {
    case .codex: "Codex"
    case .claude: "Claude"
    case .cursor: "Cursor"
    }
  }
}

func remainingQuota(for source: QuotaSource, forecast: Forecast?, cursorAccount: CursorAccount?)
  -> Double?
{
  switch source {
  case .codex, .claude: forecast?.remaining
  case .cursor:
    (cursorAccount?.activePercentUsed ?? cursorAccount?.includedPercentUsed)
      .map { max(0, min(100, 100 - $0)) }
  }
}

func menuBarQuotaText(_ remaining: Double?, stale: Bool = false) -> String {
  remaining.map { "\(Int($0))%" + (stale ? " · stale" : "") } ?? "Burn"
}

func appVersionText(short: String, build: String = "") -> String {
  build.isEmpty ? "v\(short)" : "v\(short) (\(build))"
}

func bundleVersionText(bundle: Bundle = .main) -> String {
  let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
  let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
  return appVersionText(short: short ?? "0.0.0", build: build ?? "")
}

func harnessName(_ key: String) -> String {
  switch key {
  case "codex": "Codex"
  case "claude": "Claude Code"
  case "opencode": "OpenCode"
  case "pi": "Pi"
  default: key.capitalized
  }
}

struct QuotaBlendRates: Equatable {
  var dollarsPerPercent: Double?
  var tokensPerDollar: Double?
  var tokensPerPercent: Double?
}

func quotaDayKey(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from: date)
}

func usageTotals(_ days: [DailyUsage], since start: String) -> (cost: Double, tokens: UInt64) {
  days.reduce((0, 0)) { totals, day in
    guard day.date >= start else { return totals }
    return (totals.0 + day.cost, totals.1 + (day.tokens ?? 0))
  }
}

func quotaCycleSpend(windowSpent: Double, days: [DailyUsage], since start: String) -> Double {
  windowSpent > 0 ? windowSpent : usageTotals(days, since: start).cost
}

func quotaCycleTokens(days: [DailyUsage], since start: String) -> UInt64 {
  usageTotals(days, since: start).tokens
}

func quotaTokensPerDollar(tokens: UInt64, cost: Double) -> Double? {
  tokens > 0 && cost > 0 ? Double(tokens) / cost : nil
}

func quotaBlendRates(usedPercent: Double, spent: Double, tokens: UInt64) -> QuotaBlendRates {
  QuotaBlendRates(
    dollarsPerPercent: usedPercent > 0 && spent > 0 ? spent / usedPercent : nil,
    tokensPerDollar: quotaTokensPerDollar(tokens: tokens, cost: spent),
    tokensPerPercent: tokens > 0 && usedPercent > 0 ? Double(tokens) / usedPercent : nil)
}

func quotaBlendRates(forecast: Forecast, report: HarnessReport?, daily: [DailyUsage] = [])
  -> QuotaBlendRates
{
  let start = quotaDayKey(forecast.start)
  let days = daily.isEmpty ? report?.daily ?? [] : daily
  let spent = quotaCycleSpend(
    windowSpent: report?.window?.apiEquivalentSpent ?? forecast.window.apiEquivalentSpent,
    days: days, since: start)
  let rates = quotaBlendRates(
    usedPercent: quotaUsedPercent(forecast), spent: spent,
    tokens: quotaCycleTokens(days: days, since: start))
  if rates.tokensPerDollar != nil { return rates }
  let modelTokens = report?.topModels.reduce(UInt64(0)) { $0 + $1.tokens } ?? 0
  return QuotaBlendRates(
    dollarsPerPercent: rates.dollarsPerPercent,
    tokensPerDollar: quotaTokensPerDollar(
      tokens: modelTokens, cost: report?.apiEquivalentPerMonth ?? 0),
    tokensPerPercent: rates.tokensPerPercent)
}

func quotaDollarsPerPercentLabel(_ value: Double?) -> String? {
  guard let value, value.isFinite, value > 0 else { return nil }
  return "\(currency(value)) / %"
}

func quotaTokensPerUnitLabel(_ value: Double?, unit: String) -> String? {
  guard let value, value.isFinite, value > 0 else { return nil }
  return "\(tokens(UInt64(value.rounded()))) / \(unit)"
}

func currency(_ value: Double) -> String {
  value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
}

func tokens(_ value: UInt64) -> String {
  let number = Double(value)
  if number >= 1_000_000_000 { return String(format: "%.2fB", number / 1_000_000_000) }
  if number >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
  if number >= 1000 { return String(format: "%.1fK", number / 1000) }
  return value.formatted()
}

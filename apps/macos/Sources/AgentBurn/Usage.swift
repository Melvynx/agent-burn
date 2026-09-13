import Foundation

struct SummaryReport: Codable, Sendable {
  let totals: Totals
  let agents: [AgentUsage]
  let models: [ModelUsage]
  let daily: [DailyUsage]?
  let subscription: SubscriptionReport?
  var cursorAccount: CursorAccount? = nil
  var claudeAccount: ClaudeAccount? = nil
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
  var cursorModelsCost: Double? = nil
  var cursorModelsTokens: UInt64? = nil
  var id: String { date }
}

enum CursorModelScope: String, CaseIterable, Identifiable {
  case allModels, cursorModels
  var id: String { rawValue }
  var label: String {
    switch self {
    case .allModels: "All models"
    case .cursorModels: "Cursor models"
    }
  }
}

enum SpendGranularity: String, CaseIterable, Identifiable {
  case daily, weekly, monthly
  var id: String { rawValue }
  var label: String {
    switch self {
    case .daily: "Daily"
    case .weekly: "Weekly"
    case .monthly: "Monthly"
    }
  }
  var spendTitle: String {
    switch self {
    case .daily: "Daily spend"
    case .weekly: "Weekly spend"
    case .monthly: "Monthly spend"
    }
  }
  var unit: Calendar.Component {
    switch self {
    case .daily: .day
    case .weekly: .weekOfYear
    case .monthly: .month
    }
  }
}

func spendCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.firstWeekday = 2
  calendar.minimumDaysInFirstWeek = 4
  calendar.locale = Locale(identifier: "en_US_POSIX")
  return calendar
}

func spendGranularityAuto(spanDays: Int) -> SpendGranularity {
  if spanDays > 182 { return .monthly }
  if spanDays > 62 { return .weekly }
  return .daily
}

func spendSpanDays(lower: Date, upper: Date) -> Int {
  max(1, Int((upper.timeIntervalSince(lower) / 86_400).rounded()) + 1)
}

func spendBucketStart(for date: Date, granularity: SpendGranularity, calendar: Calendar)
  -> Date
{
  switch granularity {
  case .daily:
    return calendar.startOfDay(for: date)
  case .weekly:
    return calendar.dateInterval(of: .weekOfYear, for: date)?.start
      ?? calendar.startOfDay(for: date)
  case .monthly:
    let parts = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1))
      ?? calendar.startOfDay(for: date)
  }
}

func spendBucketEnd(
  start: Date, granularity: SpendGranularity, calendar: Calendar
) -> Date {
  switch granularity {
  case .daily:
    return calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1)
      ?? start
  case .weekly:
    return calendar.date(byAdding: .day, value: 7, to: start)?.addingTimeInterval(-1)
      ?? start
  case .monthly:
    return calendar.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1)
      ?? start
  }
}

func bucketDailyUsage(
  _ days: [DailyUsage], granularity: SpendGranularity,
  calendar: Calendar = spendCalendar()
) -> [DailyUsage] {
  guard granularity != .daily else {
    return days.sorted { $0.date < $1.date }
  }
  var costByKey: [String: Double] = [:]
  var tokensByKey: [String: UInt64] = [:]
  var cursorCostByKey: [String: Double] = [:]
  var cursorTokensByKey: [String: UInt64] = [:]
  var hasCursorCost = false
  var hasCursorTokens = false
  for day in days {
    guard let date = usageDayDate(day.date) else { continue }
    let key = quotaDayKey(spendBucketStart(for: date, granularity: granularity, calendar: calendar))
    costByKey[key, default: 0] += day.cost
    tokensByKey[key, default: 0] += day.tokens ?? 0
    if let cost = day.cursorModelsCost {
      cursorCostByKey[key, default: 0] += cost
      hasCursorCost = true
    }
    if let tokens = day.cursorModelsTokens {
      cursorTokensByKey[key, default: 0] += tokens
      hasCursorTokens = true
    }
  }
  return costByKey.keys.sorted().map { key in
    DailyUsage(
      date: key, cost: costByKey[key] ?? 0,
      tokens: tokensByKey[key] ?? 0,
      cursorModelsCost: hasCursorCost ? cursorCostByKey[key] : nil,
      cursorModelsTokens: hasCursorTokens ? cursorTokensByKey[key] : nil)
  }
}

func spendBucketTooltip(
  start: Date, granularity: SpendGranularity, cost: Double,
  calendar: Calendar = spendCalendar()
) -> String {
  switch granularity {
  case .daily:
    return quotaDayKey(start) + " · " + currency(cost)
  case .weekly:
    let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
    let label =
      start.formatted(.dateTime.month(.abbreviated).day()) + " – "
      + end.formatted(.dateTime.month(.abbreviated).day())
    return label + " · " + currency(cost)
  case .monthly:
    return start.formatted(.dateTime.month(.abbreviated).year()) + " · " + currency(cost)
  }
}

enum QuotaMeterStyle {
  case weekly, promotionalCredits
  var title: String {
    switch self {
    case .weekly: "Weekly quota"
    case .promotionalCredits: "Promotional credits"
    }
  }
  var remainingCaption: String {
    switch self {
    case .weekly: "Weekly remaining"
    case .promotionalCredits: "Credits remaining"
    }
  }
  var resetTitle: String {
    switch self {
    case .weekly: "Reset in"
    case .promotionalCredits: "Expires in"
    }
  }
  var resetHelp: String {
    switch self {
    case .weekly: "Time left in this weekly limit window."
    case .promotionalCredits: "Time left before promotional credits expire."
    }
  }
  var usedHelp: String {
    switch self {
    case .weekly:
      "The current weekly limit started at this time. Used percent is measured against that full limit."
    case .promotionalCredits:
      "Used percent is measured against the promotional credit grant. The window runs until those credits expire."
    }
  }
  var chartResetLabel: String {
    switch self {
    case .weekly: "Reset"
    case .promotionalCredits: "Expires"
    }
  }
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

func quotaChartStepComponent(range: QuotaChartRange, window: ClosedRange<Date>)
  -> Calendar.Component
{
  if range == .today { return .hour }
  let days = window.upperBound.timeIntervalSince(window.lowerBound) / 86_400
  return days > 45 ? .month : .day
}

func quotaChartThinnedDates(_ dates: [Date], limit: Int = 6) -> [Date] {
  guard dates.count > limit, limit >= 2 else { return dates }
  let last = dates.count - 1
  var picked: [Date] = []
  for index in 0..<limit {
    let date = dates[Int((Double(index) * Double(last) / Double(limit - 1)).rounded())]
    if picked.last != date { picked.append(date) }
  }
  return picked
}

func quotaChartGridDates(
  range: QuotaChartRange, forecast: Forecast, now: Date, calendar: Calendar = .current
) -> [Date] {
  let window = quotaChartWindow(range: range, forecast: forecast, now: now, calendar: calendar)
  return quotaChartSteppedDates(
    in: window,
    component: quotaChartStepComponent(range: range, window: window),
    calendar: calendar)
}

func quotaChartAxisDates(
  range: QuotaChartRange, forecast: Forecast, now: Date, calendar: Calendar = .current
) -> [Date] {
  let window = quotaChartWindow(range: range, forecast: forecast, now: now, calendar: calendar)
  let grid = quotaChartGridDates(range: range, forecast: forecast, now: now, calendar: calendar)
  if range == .today {
    return grid.enumerated().compactMap { offset, date in
      offset % 3 == 0 || offset == grid.count - 1 ? date : nil
    }
  }
  let scale = quotaChartScale(range: range, forecast: forecast, now: now, calendar: calendar)
  let marks = grid.map { date in
    let midday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    return min(max(midday, scale.lowerBound), scale.upperBound)
  }
  let days = window.upperBound.timeIntervalSince(window.lowerBound) / 86_400
  return days > 45 ? quotaChartThinnedDates(marks) : marks
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
  if let first = marks.first, let last = marks.last,
    last.timeIntervalSince(first) > 45 * 86_400
  {
    return date.formatted(.dateTime.month(.abbreviated))
  }
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

func quotaChartDrawnSamples(
  _ samples: [QuotaSample], stepGap: TimeInterval = 2 * 3_600
) -> [QuotaSample] {
  let points = quotaChartCollapsedSamples(samples)
  guard var previous = points.first else { return [] }
  var result = [previous]
  for sample in points.dropFirst() {
    if sample.date.timeIntervalSince(previous.date) <= stepGap,
      abs(sample.remaining - previous.remaining) >= 0.05
    {
      result.append(QuotaSample(date: sample.date, remaining: previous.remaining))
    }
    result.append(sample)
    previous = sample
  }
  return result
}

private func quotaChartCollapsedSamples(_ samples: [QuotaSample]) -> [QuotaSample] {
  let sorted = samples.sorted { $0.date < $1.date }
  guard var previous = sorted.first else { return [] }
  var result = [previous]
  for sample in sorted.dropFirst() {
    if abs(sample.remaining - previous.remaining) >= 0.05 {
      if result.last != previous { result.append(previous) }
      result.append(sample)
    }
    previous = sample
  }
  if let last = sorted.last, result.last != last { result.append(last) }
  return result
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

func remainingQuota(
  for source: QuotaSource, forecast: Forecast?, cursorAccount: CursorAccount?,
  claudeAccount: ClaudeAccount? = nil
) -> Double? {
  switch source {
  case .codex:
    return forecast?.remaining
  case .claude:
    return forecast?.remaining
      ?? claudeAccount?.weeklyUsedPercent.map { max(0, min(100, 100 - $0)) }
  case .cursor:
    if let forecast { return forecast.remaining }
    return (cursorAccount?.activePercentUsed ?? cursorAccount?.includedPercentUsed)
      .map { max(0, min(100, 100 - $0)) }
  }
}

func cursorHasPromotionalCredits(_ account: CursorAccount?) -> Bool {
  account?.grants.contains { $0.kind == "promo" && ($0.remainingUSD ?? 0) > 0 } ?? false
}

func isCursorModel(_ name: String) -> Bool {
  let model = name.lowercased()
  return model.contains("composer") || model.contains("cursor") || model == "auto"
    || model.hasPrefix("auto-")
}

func dailyUsage(_ days: [DailyUsage], scope: CursorModelScope) -> [DailyUsage] {
  guard scope == .cursorModels else { return days }
  guard days.contains(where: { $0.cursorModelsCost != nil }) else { return days }
  return days.map {
    DailyUsage(
      date: $0.date, cost: $0.cursorModelsCost ?? 0,
      tokens: $0.cursorModelsTokens ?? $0.tokens)
  }
}

func modelUsage(_ models: [ModelUsage], scope: CursorModelScope) -> [ModelUsage] {
  scope == .cursorModels ? models.filter { isCursorModel($0.model) } : models
}

func cursorMeterForecast(account: CursorAccount?, now: Date, stored: Forecast?) -> Forecast? {
  if let stored { return stored }
  guard let account, let reading = cursorQuotaReading(account, now: now) else { return nil }
  return Forecast(window: reading.window, observedAt: reading.date, isLive: true)
}

func cursorQuotaReading(_ account: CursorAccount, now: Date = .now) -> QuotaReading? {
  guard cursorHasPromotionalCredits(account) else { return nil }
  let used = account.activePercentUsed ?? cursorGrantUsedPercent(account)
  guard let used, used.isFinite, (0...100).contains(used) else { return nil }
  let reset =
    account.grants.compactMap { grant -> Date? in
      guard grant.kind == "promo", (grant.remainingUSD ?? 0) > 0, let ms = grant.expiresAtMs else {
        return nil
      }
      return Date(timeIntervalSince1970: ms / 1000)
    }.min()
    ?? account.billingCycleEndMs.map { Date(timeIntervalSince1970: $0 / 1000) }
  guard let reset, reset > now else { return nil }
  let year: TimeInterval = 365 * 86_400
  let start = min(now, reset.addingTimeInterval(-year))
  let minutes = reset.timeIntervalSince(start) / 60
  guard minutes > 0 else { return nil }
  let elapsed = now.timeIntervalSince(start) / reset.timeIntervalSince(start) * 100
  let spent = account.grants.filter { $0.kind == "promo" }.compactMap { grant -> Double? in
    guard let total = grant.totalUSD, let remaining = grant.remainingUSD else { return nil }
    return max(0, total - remaining)
  }.reduce(0, +)
  let window = QuotaWindow(
    windowMinutes: minutes, usedPercent: used, elapsedPercent: elapsed,
    apiEquivalentSpent: spent)
  guard window.isValid else { return nil }
  return QuotaReading(agent: "cursor", observedAt: now.timeIntervalSince1970 * 1000, window: window)
}

private func cursorGrantUsedPercent(_ account: CursorAccount) -> Double? {
  let promo = account.grants.filter { $0.kind == "promo" && ($0.remainingUSD ?? 0) > 0 }
  let remaining = promo.compactMap(\.remainingUSD).reduce(0, +)
  let total = promo.compactMap(\.totalUSD).reduce(0, +)
  guard total > 0 else { return nil }
  return max(0, min(100, (total - remaining) / total * 100))
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

func usageDayDate(_ value: String) -> Date? {
  let parts = value.split(separator: "-")
  guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]),
    let day = Int(parts[2])
  else { return nil }
  var calendar = Calendar(identifier: .gregorian)
  calendar.locale = Locale(identifier: "en_US_POSIX")
  return calendar.date(from: DateComponents(year: year, month: month, day: day))
}

func activityChartDomain(
  period: UsagePeriod, knownDates: [String], now: Date = .now, resetStart: Date? = nil
) -> ClosedRange<Date>? {
  let bounds = period.dateBounds(now: now, resetStart: resetStart)
  guard let end = usageDayDate(bounds.1) else { return nil }
  if let startBound = bounds.0, let start = usageDayDate(startBound), start <= end {
    return start...end
  }
  guard period == .all, let start = knownDates.compactMap(usageDayDate).min(), start <= end else {
    return nil
  }
  return start...end
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

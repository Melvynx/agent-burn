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
  var connectsRecordedGaps: Bool {
    switch self {
    case .rte, .rtd, .week: true
    case .today, .month: false
    }
  }
}

func quotaChartWindow(range: QuotaChartRange, forecast: Forecast, now: Date) -> ClosedRange<Date> {
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
    start = Calendar.current.startOfDay(for: cursor)
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

func quotaChartAxisDates(range: QuotaChartRange, forecast: Forecast, now: Date) -> [Date] {
  switch range {
  case .rte:
    return [forecast.start, forecast.reset]
  case .rtd:
    return [
      forecast.start, quotaChartWindow(range: range, forecast: forecast, now: now).upperBound,
    ]
  case .today, .week, .month:
    return []
  }
}

func quotaDateText(_ date: Date) -> String {
  date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
}

func quotaLimitSummary(_ forecast: Forecast) -> String {
  let used = max(0, min(100, forecast.window.usedPercent))
  return
    "Limit: \(quotaDateText(forecast.start)) · \(used.formatted(.number.precision(.fractionLength(0))))% used"
}

func quotaTimeRemaining(_ forecast: Forecast, now: Date) -> String {
  let seconds = max(0, forecast.reset.timeIntervalSince(min(now, forecast.reset)))
  let days = Int(seconds / 86_400)
  let hours = Int((seconds - Double(days) * 86_400) / 3_600)
  if days > 0 { return "\(days)d \(hours)h left" }
  if hours > 0 { return "\(hours)h left" }
  return "Less than 1h left"
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

func resetSummary(_ resets: [QuotaReset]) -> String {
  let scheduled = resets.filter(\.scheduled).count
  guard !resets.isEmpty else { return "No quota resets recorded" }
  return
    "\(resets.count) recorded · \(scheduled) scheduled, \(resets.count - scheduled) possible"
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
    cursorAccount?.includedPercentUsed.map { max(0, min(100, 100 - $0)) }
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

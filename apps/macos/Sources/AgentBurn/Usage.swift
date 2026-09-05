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

struct QuotaSample: Codable, Sendable {
  let date: Date
  let remaining: Double
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

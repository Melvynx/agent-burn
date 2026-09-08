import Foundation

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

struct QuotaSample: Codable, Sendable {
  let date: Date
  let remaining: Double
}

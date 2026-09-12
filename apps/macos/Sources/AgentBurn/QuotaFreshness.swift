import Foundation

extension UsageStore {
  func quotaIsStale(at date: Date) -> Bool {
    guard remainingPercent != nil else { return false }
    if quotaSource == .cursor {
      if let forecast = forecast(for: "cursor"), forecast.isLive {
        return !forecast.isFresh(at: date) || quotaError(for: "cursor") != nil
      }
      guard let updated = updated["summary"] else { return true }
      return date.timeIntervalSince(updated) > 90 || errors["summary"] != nil
    }
    return forecast(for: quotaSource.rawValue)?.isFresh(at: date) != true
      || quotaError(for: quotaSource.rawValue) != nil
  }
}

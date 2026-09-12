import Foundation

struct QuotaReading: Codable, Sendable {
  let agent: String
  let observedAt: Double
  let window: QuotaWindow
  var date: Date { Date(timeIntervalSince1970: observedAt / 1000) }
  /// Start of the limit window this reading belongs to, derived from the
  /// provider-reported elapsed percent. Readings from the same cycle share
  /// the same start; a provider hiccup can briefly replay a superseded
  /// cycle (same old start, new timestamp), which must not rewind the chart.
  var windowStart: Date {
    date.addingTimeInterval(-window.elapsedPercent / 100 * max(1, window.windowMinutes * 60))
  }
}

struct QuotaReset: Equatable {
  let date: Date
  let scheduled: Bool
}

struct QuotaHistory: Codable {
  var version = 1
  var readings: [String: [String: [QuotaReading]]] = [:]
  var failures: [String: [String: String]] = [:]

  mutating func record(_ reading: QuotaReading, source: String) {
    guard reading.observedAt.isFinite, reading.window.isValid,
      reading.observedAt > (latest(agent: reading.agent, source: source)?.observedAt ?? 0)
    else { return }
    readings[source, default: [:]][reading.agent, default: []].append(reading)
    failures[source]?[reading.agent] = nil
  }

  mutating func fail(agent: String, source: String, message: String) {
    failures[source, default: [:]][agent] = message
  }

  func latest(agent: String, source: String) -> QuotaReading? {
    readings[source]?[agent]?.last
  }

  /// Readings with stale replays removed. A new window start means a genuine
  /// reset and starts a new segment, but a reading whose window start matches
  /// an older, superseded segment is a provider replay of that old cycle and
  /// is skipped so it cannot carve a dip into the chart.
  func cycleConsistentReadings(agent: String, source: String) -> [QuotaReading] {
    var kept: [QuotaReading] = []
    var segmentStarts: [Date] = []
    for reading in readings[source]?[agent] ?? [] {
      let start = reading.windowStart
      if let last = segmentStarts.last, abs(start.timeIntervalSince(last)) <= 300 {
        kept.append(reading)
      } else if segmentStarts.contains(where: { abs(start.timeIntervalSince($0)) <= 300 }) {
        continue
      } else {
        segmentStarts.append(start)
        kept.append(reading)
      }
    }
    return kept
  }

  func samples(agent: String, source: String) -> [QuotaSample] {
    cycleConsistentReadings(agent: agent, source: source).map {
      QuotaSample(date: $0.date, remaining: 100 - $0.window.usedPercent)
    }
  }

  func resets(agent: String, source: String) -> [QuotaReset] {
    let points = cycleConsistentReadings(agent: agent, source: source)
    var found: [QuotaReset] = []
    for (index, reading) in points.enumerated() {
      guard index > 0 else { continue }
      let previous = points[index - 1]
      let remaining = 100 - reading.window.usedPercent
      let previousRemaining = 100 - previous.window.usedPercent
      guard remaining > previousRemaining + 1 else { continue }
      found.append(
        QuotaReset(
          date: reading.date,
          scheduled: previous.window.elapsedPercent >= 80 && reading.window.elapsedPercent <= 20
        ))
    }
    return found
  }
}

struct QuotaHistoryFile {
  let directory: URL
  var url: URL { directory.appendingPathComponent("quota-archive.json") }
  private var backup: URL { url.appendingPathExtension("bak") }

  private func decode(_ data: Data) throws -> QuotaHistory {
    let history = try JSONDecoder().decode(QuotaHistory.self, from: data)
    guard history.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
    return history
  }

  func load() throws -> QuotaHistory? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return FileManager.default.fileExists(atPath: backup.path)
        ? try decode(Data(contentsOf: backup)) : nil
    }
    do { return try decode(Data(contentsOf: url)) } catch {
      guard FileManager.default.fileExists(atPath: backup.path) else { throw error }
      return try decode(Data(contentsOf: backup))
    }
  }

  func save(_ history: QuotaHistory) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    if let data = try? Data(contentsOf: url), (try? decode(data)) != nil {
      try data.write(to: backup, options: .atomic)
    }
    try JSONEncoder().encode(history).write(to: url, options: .atomic)
  }
}

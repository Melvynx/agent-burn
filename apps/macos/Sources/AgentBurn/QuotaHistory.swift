import Foundation

struct QuotaReading: Codable, Sendable {
  let agent: String
  let observedAt: Double
  let window: QuotaWindow
  var date: Date { Date(timeIntervalSince1970: observedAt / 1000) }
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

  func samples(agent: String, source: String) -> [QuotaSample] {
    (readings[source]?[agent] ?? []).map {
      QuotaSample(date: $0.date, remaining: 100 - $0.window.usedPercent)
    }
  }

  func resets(agent: String, source: String) -> [QuotaReset] {
    let points = readings[source]?[agent] ?? []
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

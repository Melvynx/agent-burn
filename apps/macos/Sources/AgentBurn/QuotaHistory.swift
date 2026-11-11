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

  @discardableResult
  mutating func record(_ reading: QuotaReading, source: String) -> Bool {
    guard reading.observedAt.isFinite, reading.window.isValid,
      reading.observedAt > (latest(agent: reading.agent, source: source)?.observedAt ?? 0)
    else { return false }
    readings[source, default: [:]][reading.agent, default: []].append(reading)
    failures[source]?[reading.agent] = nil
    return true
  }

  mutating func fail(agent: String, source: String, message: String) {
    failures[source, default: [:]][agent] = message
  }

  func latest(agent: String, source: String) -> QuotaReading? {
    readings[source]?[agent]?.last
  }

  /// The newest reading safe to show as the live meter. On a weekly window a
  /// reading far above the lowest one of the last half hour is an unconfirmed
  /// provider over-count, so the latest plausible reading stands in for it.
  func current(agent: String, source: String) -> QuotaReading? {
    guard let all = readings[source]?[agent], let newest = all.last else { return nil }
    let recent = all.reversed().prefix { Self.isRecent($0, to: newest) }
    guard let floor = recent.map(\.window.usedPercent).min() else { return newest }
    return recent.first { !Self.isOverCount($0, floor: floor) } ?? newest
  }

  /// Weekly usage cannot roughly double within half an hour of one window.
  private static func isRecent(_ reading: QuotaReading, to newest: QuotaReading) -> Bool {
    newest.date.timeIntervalSince(reading.date) <= 1800
      && abs(reading.windowStart.timeIntervalSince(newest.windowStart)) <= 300
  }

  private static func isOverCount(_ reading: QuotaReading, floor: Double) -> Bool {
    reading.window.windowMinutes >= 2 * 24 * 60 && reading.window.usedPercent > floor * 1.5 + 3
  }

  /// Readings with stale replays and over-counts removed. A new window start
  /// means a genuine reset and starts a new segment, but a reading whose window
  /// start matches an older, superseded segment is a provider replay of that old
  /// cycle and is skipped so it cannot carve a dip into the chart. Usage never
  /// falls within one window, so a later, lower reading of the same segment
  /// proves the higher ones before it were provider over-counts (Codex served
  /// 99% while enforcing 49%); those are skipped too, and a trailing jump is
  /// held back the same way `current` holds it.
  func cycleConsistentReadings(agent: String, source: String) -> [QuotaReading] {
    var kept: [(reading: QuotaReading, segment: Int)] = []
    var segmentStarts: [Date] = []
    for reading in readings[source]?[agent] ?? [] {
      let start = reading.windowStart
      if let last = segmentStarts.last, abs(start.timeIntervalSince(last)) <= 300 {
        kept.append((reading, segmentStarts.count - 1))
      } else if segmentStarts.contains(where: { abs(start.timeIntervalSince($0)) <= 300 }) {
        continue
      } else {
        segmentStarts.append(start)
        kept.append((reading, segmentStarts.count - 1))
      }
    }
    var lowestLater: [Int: Double] = [:]
    var consistent: [QuotaReading] = []
    for (reading, segment) in kept.reversed() {
      let used = reading.window.usedPercent
      if let floor = lowestLater[segment], used > floor + 1 { continue }
      lowestLater[segment] = min(used, lowestLater[segment] ?? used)
      consistent.append(reading)
    }
    var chronological = Array(consistent.reversed())
    if let newest = chronological.last,
      let floor = consistent.prefix(while: { Self.isRecent($0, to: newest) })
        .map(\.window.usedPercent).min()
    {
      while let last = chronological.last, Self.isOverCount(last, floor: floor) {
        chronological.removeLast()
      }
    }
    return chronological
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

  var journal: QuotaJournal { QuotaJournal(directory: directory) }

  /// Archive, then its backup, then a rebuild from the append-only CSV journal.
  func load() throws -> QuotaHistory? { try loadWithOrigin()?.history }

  /// `fromArchive` tells whether the primary archive itself decoded, so a save
  /// can back it up without reading and decoding it a second time.
  private func loadWithOrigin() throws -> (history: QuotaHistory, fromArchive: Bool)? {
    var failure: Error?
    for candidate in [url, backup] where FileManager.default.fileExists(atPath: candidate.path) {
      do { return (try decode(Data(contentsOf: candidate)), candidate == url) } catch {
        failure = failure ?? error
      }
    }
    if let rebuilt = try? journal.load() { return (rebuilt, false) }
    if let failure { throw failure }
    return nil
  }

  /// Merges readings into the latest archive on disk so concurrent writers
  /// (the app and the background collector) never drop each other's rows.
  /// `strict` refuses to start over when every stored copy is unreadable.
  @discardableResult
  func commit(
    _ readings: [QuotaReading], source: String,
    failures: [String: String?] = [:], strict: Bool = false
  ) throws -> QuotaHistory {
    let loaded: (history: QuotaHistory, fromArchive: Bool)?
    if strict { loaded = try loadWithOrigin() } else { loaded = try? loadWithOrigin() }
    var history = loaded?.history ?? QuotaHistory()
    try? journal.seedIfMissing(from: history)
    let accepted = readings.filter { history.record($0, source: source) }
    for (agent, message) in failures {
      if let message {
        history.fail(agent: agent, source: source, message: message)
      } else {
        history.failures[source]?[agent] = nil
      }
    }
    try? journal.append(accepted.map { (source, $0) })
    try save(history, archiveIsValid: loaded?.fromArchive ?? false)
    return history
  }

  func save(_ history: QuotaHistory) throws { try save(history, archiveIsValid: nil) }

  private func save(_ history: QuotaHistory, archiveIsValid: Bool?) throws {
    let manager = FileManager.default
    try manager.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let valid =
      archiveIsValid ?? ((try? Data(contentsOf: url)).flatMap { try? decode($0) } != nil)
    if valid, manager.fileExists(atPath: url.path) {
      // copyItem clones on APFS: the backup shares blocks instead of rewriting the archive.
      let staged = backup.appendingPathExtension("tmp")
      try? manager.removeItem(at: staged)
      try manager.copyItem(at: url, to: staged)
      guard rename(staged.path, backup.path) == 0 else {
        try? manager.removeItem(at: staged)
        throw CocoaError(.fileWriteUnknown)
      }
    }
    try JSONEncoder().encode(history).write(to: url, options: .atomic)
  }
}

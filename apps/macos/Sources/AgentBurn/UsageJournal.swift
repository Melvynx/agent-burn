import Foundation

struct UsageSnapshot: Codable {
  let date: Date
  let source: String
  let payload: Data
}

struct UsageJournal {
  let directory: URL
  private var url: URL { directory.appendingPathComponent("usage-journal.json") }

  func record(_ cache: ReportCache) throws {
    guard let snapshot = Self.snapshot(from: cache) else { return }
    var snapshots = (try? records()) ?? []
    if snapshots.last?.source == snapshot.source, snapshots.last?.payload == snapshot.payload {
      return
    }
    snapshots.append(snapshot)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(snapshots).write(to: url, options: .atomic)
  }

  func records() throws -> [UsageSnapshot] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    return try JSONDecoder().decode([UsageSnapshot].self, from: Data(contentsOf: url))
  }

  func latest(source: String) throws -> ReportCache? {
    try records().last { $0.source == source }.map(Self.cache(from:))
  }

  private static func snapshot(from cache: ReportCache) -> UsageSnapshot? {
    let saved = cache.summaries["all"] ?? cache.summaries.values.max { $0.date < $1.date }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let saved, let payload = try? encoder.encode(saved.report) else { return nil }
    return UsageSnapshot(date: saved.date, source: cache.source, payload: payload)
  }

  fileprivate static func cache(from snapshot: UsageSnapshot) throws -> ReportCache {
    let report = try JSONDecoder().decode(SummaryReport.self, from: snapshot.payload)
    return ReportCache(
      source: snapshot.source,
      summaries: ["all": CachedReport(report: report, date: snapshot.date)],
      harnesses: [:])
  }
}

struct ReportCacheFile {
  let directory: URL
  var url: URL { directory.appendingPathComponent("report-cache.json") }
  private var backup: URL { url.appendingPathExtension("bak") }
  private var journal: UsageJournal { UsageJournal(directory: directory) }

  func load(source: String) throws -> ReportCache? {
    if let cache = (try? decode(url)) ?? (try? decode(backup)), cache.source == source {
      return cache
    }
    return try journal.latest(source: source)
  }

  func save(_ cache: ReportCache) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    if let previous = try? Data(contentsOf: url), (try? decode(url)) != nil {
      try previous.write(to: backup, options: .atomic)
    }
    try JSONEncoder().encode(cache).write(to: url, options: .atomic)
    try journal.record(cache)
  }

  private func decode(_ file: URL) throws -> ReportCache {
    try JSONDecoder().decode(ReportCache.self, from: Data(contentsOf: file))
  }
}

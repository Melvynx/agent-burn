import Foundation

struct UsageSnapshot: Codable {
  let date: Date
  let source: String
  let payload: Data
}

struct UsageJournal {
  let directory: URL
  private var url: URL { directory.appendingPathComponent("usage-journal.jsonl") }
  /// Single JSON array rewritten on every refresh; migrated once to JSON Lines.
  private var legacyURL: URL { directory.appendingPathComponent("usage-journal.json") }

  /// Appends one line per changed report. The history only grows, so a refresh
  /// writes one snapshot instead of rewriting every snapshot ever recorded.
  func record(_ cache: ReportCache) throws {
    guard let snapshot = Self.snapshot(from: cache) else { return }
    migrateLegacyIfNeeded()
    let tail = try? lastRecord()
    if let last = tail?.snapshot, last.source == snapshot.source, last.payload == snapshot.payload {
      return
    }
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var line = try JSONEncoder().encode(snapshot)
    line.append(Self.newline)
    guard FileManager.default.fileExists(atPath: url.path) else {
      try line.write(to: url, options: .atomic)
      return
    }
    // A crash mid-append leaves a partial line; start on a fresh one so it stays isolated.
    if tail?.endsWithNewline == false { line.insert(Self.newline, at: 0) }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
  }

  func records() throws -> [UsageSnapshot] {
    migrateLegacyIfNeeded()
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let decoder = JSONDecoder()
    return try Data(contentsOf: url).split(separator: Self.newline).compactMap {
      try? decoder.decode(UsageSnapshot.self, from: Data($0))
    }
  }

  func latest(source: String) throws -> ReportCache? {
    try records().last { $0.source == source }.map(Self.cache(from:))
  }

  private static let newline = UInt8(ascii: "\n")

  /// Reads only the end of the file, growing the window until a whole line fits.
  private func lastRecord() throws -> (snapshot: UsageSnapshot?, endsWithNewline: Bool)? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let size = try handle.seekToEnd()
    guard size > 0 else { return (nil, true) }
    var window: UInt64 = 256 * 1024
    while true {
      let start = size > window ? size - window : 0
      try handle.seek(toOffset: start)
      let data = try handle.readToEnd() ?? Data()
      let lines = data.split(separator: Self.newline)
      if let last = lines.last, start == 0 || lines.count > 1 {
        return (
          try? JSONDecoder().decode(UsageSnapshot.self, from: Data(last)),
          data.last == Self.newline
        )
      }
      if start == 0 { return (nil, data.last == Self.newline) }
      window *= 4
    }
  }

  private func migrateLegacyIfNeeded() {
    let manager = FileManager.default
    guard manager.fileExists(atPath: legacyURL.path), !manager.fileExists(atPath: url.path),
      let legacy = try? JSONDecoder().decode(
        [UsageSnapshot].self, from: Data(contentsOf: legacyURL))
    else { return }
    let encoder = JSONEncoder()
    var data = Data()
    for snapshot in legacy {
      guard let line = try? encoder.encode(snapshot) else { continue }
      data.append(line)
      data.append(Self.newline)
    }
    guard (try? data.write(to: url, options: .atomic)) != nil else { return }
    try? manager.removeItem(at: legacyURL)
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

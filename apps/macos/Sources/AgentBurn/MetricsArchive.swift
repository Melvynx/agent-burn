import Foundation

/// Daily high-water marks: snapshots are never added together or expired.
/// This preserves observed usage when a provider drops days or partial logs.
struct MetricsArchive: Codable {
  var version = 1
  var agents: [String: [String: DailyUsage]] = [:]
  var savedAt: Date?

  mutating func ingest(_ report: SummaryReport) {
    for agent in report.agents {
      for day in agent.daily ?? [] where day.cost.isFinite && day.cost >= 0 {
        let old = agents[agent.agent]?[day.date]
        agents[agent.agent, default: [:]][day.date] = DailyUsage(
          date: day.date, cost: max(old?.cost ?? 0, day.cost),
          tokens: max(old?.tokens ?? 0, day.tokens ?? 0))
      }
    }
  }

  func report(period: UsagePeriod, live: SummaryReport?, now: Date = .now) -> SummaryReport {
    let bounds = period.dateBounds(now: now)
    let usages = agents.keys.sorted().compactMap { name -> AgentUsage? in
      let days = (agents[name] ?? [:]).values.filter {
        (bounds.0 == nil || $0.date >= bounds.0!) && $0.date <= bounds.1
      }.sorted { $0.date < $1.date }
      guard !days.isEmpty else { return nil }
      let current = live?.agents.first { $0.agent == name }
      return AgentUsage(
        agent: name, totalCost: days.reduce(0) { $0 + $1.cost },
        totalTokens: days.reduce(0) { $0 + ($1.tokens ?? 0) },
        models: current?.models, daily: days, tokenBreakdown: current?.tokenBreakdown)
    }
    let grouped = Dictionary(grouping: usages.flatMap { $0.daily ?? [] }, by: \.date)
    let days = grouped.keys.sorted().map { date in
      DailyUsage(
        date: date, cost: grouped[date]!.reduce(0) { $0 + $1.cost },
        tokens: grouped[date]!.reduce(0) { $0 + ($1.tokens ?? 0) })
    }
    var report = SummaryReport(
      totals: Totals(
        totalCost: usages.reduce(0) { $0 + $1.totalCost },
        totalTokens: usages.reduce(0) { $0 + $1.totalTokens }),
      agents: usages, models: live?.models ?? [], daily: days, subscription: live?.subscription)
    report.cursorAccount = live?.cursorAccount
    return report
  }
}

extension UsagePeriod {
  func dateBounds(now: Date) -> (String?, String) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    let today = calendar.startOfDay(for: now)
    let end = self == .yesterday ? calendar.date(byAdding: .day, value: -1, to: today)! : today
    let start: Date?
    switch self {
    case .all: start = nil
    case .today, .yesterday: start = end
    case .wtd: start = calendar.dateInterval(of: .weekOfYear, for: now)?.start
    case .mtd: start = calendar.dateInterval(of: .month, for: now)?.start
    case .ytd: start = calendar.dateInterval(of: .year, for: now)?.start
    case .week: start = calendar.date(byAdding: .day, value: -6, to: today)
    case .month: start = calendar.date(byAdding: .day, value: -29, to: today)
    }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return (start.map(formatter.string), formatter.string(from: end))
  }
}

struct MetricsArchiveFile {
  let url: URL
  private var backup: URL { url.appendingPathExtension("bak") }

  private func decode(_ data: Data) throws -> MetricsArchive {
    let archive = try JSONDecoder().decode(MetricsArchive.self, from: data)
    guard archive.version == 1 else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return archive
  }

  func load() throws -> MetricsArchive? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      if FileManager.default.fileExists(atPath: backup.path) {
        return try decode(Data(contentsOf: backup))
      }
      return nil
    }
    do { return try decode(Data(contentsOf: url)) } catch {
      guard FileManager.default.fileExists(atPath: backup.path) else { throw error }
      return try decode(Data(contentsOf: backup))
    }
  }

  func save(_ archive: MetricsArchive) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    // Never replace the recovery copy with a corrupt primary file.
    if let previous = try? Data(contentsOf: url), (try? decode(previous)) != nil {
      try previous.write(to: backup, options: .atomic)
    }
    var saved = archive
    saved.savedAt = .now
    try JSONEncoder().encode(saved).write(to: url, options: .atomic)
  }
}

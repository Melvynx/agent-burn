import SwiftUI

enum UsagePeriod: String, CaseIterable, Identifiable {
  case today, yesterday, wtd, mtd, week, month, ytd, all
  var id: String { rawValue }
  var arguments: [String] { ["summary"] + (self == .all ? [] : [rawValue]) + ["--value"] }
  var label: String {
    switch self {
    case .today: "Today"
    case .all: "All time"
    case .yesterday: "Yesterday"
    case .wtd: "Week to date"
    case .ytd: "Year to date"
    case .week: "Last 7 days"
    case .mtd: "This month"
    case .month: "Last 30 days"
    }
  }
}

@MainActor
@Observable
final class UsageStore {
  var summary: SummaryReport?
  var reports: [String: HarnessReport] = [:]
  var updated: [String: Date] = [:]
  var errors: [String: String] = [:]
  var isLoading = false
  var period = UsagePeriod.mtd {
    didSet {
      guard oldValue != period else { return }
      Task { await changePeriod() }
    }
  }
  var selection = "summary"
  var customPath: String { didSet { defaults.set(customPath, forKey: "cliPath") } }
  var codexHomes: String { didSet { defaults.set(codexHomes, forKey: "codexHomes") } }
  var offline: Bool { didSet { defaults.set(offline, forKey: "offline") } }
  var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: "refreshMinutes") } }
  private var history: [String: [QuotaSample]] = [:]
  private let defaults: UserDefaults
  private let historyURL: URL
  private let cacheURL: URL
  private var cache: ReportCache?
  private var archive = MetricsArchive()
  private var archiveWritable = true
  var archiveURL: URL {
    cacheURL.deletingLastPathComponent().appendingPathComponent("metrics-history.json")
  }
  var archivedDayCount: Int { Set(archive.agents.values.flatMap { $0.keys }).count }
  var recoveredCursor: AgentUsage? {
    cache?.summaries["cursor-recovered"]?.report.agents.first { $0.agent == "cursor" }
  }
  func archivedDays(for agent: String?) -> Int {
    guard let agent else { return archivedDayCount }
    return archive.agents[agent]?.count ?? 0
  }
  var knownAgents: [String] {
    Set(
      (summary?.agents.map(\.agent) ?? []) + (cache?.agentNames ?? []) + Array(archive.agents.keys)
    ).sorted()
  }
  private var sourceKey: String { customPath + "|" + codexHomes + "|" + String(offline) }
  private var started = false

  init(defaults: UserDefaults = .standard, period: UsagePeriod = .all, storageDirectory: URL? = nil)
  {
    self.period = period
    self.defaults = defaults
    customPath = defaults.string(forKey: "cliPath") ?? ""
    codexHomes =
      defaults.string(forKey: "codexHomes")
      ?? SourcePaths.codexHomes(
        home: FileManager.default.homeDirectoryForCurrentUser.path,
        inherited: ProcessInfo.processInfo.environment["CODEX_HOME"])
    offline = defaults.bool(forKey: "offline")
    refreshMinutes = max(5, defaults.integer(forKey: "refreshMinutes"))
    historyURL =
      (storageDirectory
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Agent Burn"))
      .appendingPathComponent("quota-history.json")
    cacheURL = historyURL.deletingLastPathComponent().appendingPathComponent("report-cache.json")
    defaults.set(codexHomes, forKey: "codexHomes")
    if let data = try? Data(contentsOf: historyURL),
      let decoded = try? JSONDecoder().decode([String: [QuotaSample]].self, from: data)
    {
      history = decoded
    }
    if let data = try? Data(contentsOf: cacheURL),
      let decoded = try? JSONDecoder().decode(ReportCache.self, from: data),
      decoded.source == sourceKey
    {
      cache = decoded
      summary = decoded.summaries[period.rawValue]?.report
      updated["summary"] = decoded.summaries[period.rawValue]?.date
      for (agent, saved) in decoded.harnesses {
        reports[agent] = saved.report
        updated[agent] = saved.date
      }
    }
    do {
      archive = try MetricsArchiveFile(url: archiveURL).load() ?? MetricsArchive()
      for saved in cache?.summaries.values ?? [String: CachedReport<SummaryReport>]().values {
        archive.ingest(saved.report)
      }
      if !archive.agents.isEmpty {
        try MetricsArchiveFile(url: archiveURL).save(archive)
        summary = archive.report(period: period, live: summary)
      }
    } catch {
      archiveWritable = false
      errors["archive"] =
        "Metrics history could not be read or saved. Existing files have been preserved."
    }
  }

  func start() async {
    guard !started else { return }
    started = true
    await refresh()
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(refreshMinutes * 60))
      if !Task.isCancelled { await refresh() }
    }
    started = false
  }

  func refresh() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    let executable: URL
    do { executable = try CLIClient.executable(customPath: customPath) } catch {
      for key in ["summary", "codex", "claude"] { errors[key] = error.localizedDescription }
      return
    }
    let selectedPeriod = period
    let useOffline = offline
    if cache?.source != sourceKey {
      cache = ReportCache(source: sourceKey, summaries: [:], harnesses: [:])
      summary = nil
      reports = [:]
      updated = [:]
    }
    async let summaryUpdate: () = loadSummary(
      executable, period: selectedPeriod, offline: useOffline)
    async let codexUpdate: () = loadHarness("codex", executable: executable, offline: useOffline)
    async let claudeUpdate: () = loadHarness("claude", executable: executable, offline: useOffline)
    _ = await (summaryUpdate, codexUpdate, claudeUpdate)
    if selectedPeriod != .all {
      await loadSummary(executable, period: .all, offline: useOffline)
    }
  }

  private func loadSummary(_ executable: URL, period: UsagePeriod, offline: Bool) async {
    do {
      let source = sourceKey
      let report = try await CLIClient.read(
        SummaryReport.self, executable: executable,
        arguments: period.arguments, offline: offline, environment: ["CODEX_HOME": codexHomes])
      guard source == sourceKey else { return }
      cache?.summaries[period.rawValue] = CachedReport(report: report, date: .now)
      saveCache()
      archive.ingest(report)
      if archiveWritable {
        do {
          try MetricsArchiveFile(url: archiveURL).save(archive)
          errors["archive"] = nil
        } catch {
          errors["archive"] = "Daily metrics could not be saved. Check the history file location."
        }
      }
      summary = archive.report(
        period: self.period, live: cache?.summaries[self.period.rawValue]?.report)
      updated["summary"] = .now
      errors["summary"] = nil
    } catch { errors["summary"] = error.localizedDescription }
  }

  private func loadHarness(_ agent: String, executable: URL, offline: Bool) async {
    do {
      let source = sourceKey
      let report = try await CLIClient.read(
        HarnessReport.self, executable: executable,
        arguments: ["harness", agent], offline: offline, environment: ["CODEX_HOME": codexHomes])
      guard source == sourceKey else { return }
      let date = Date.now
      cache?.harnesses[agent] = CachedReport(report: report, date: date)
      saveCache()
      reports[agent] = report
      updated[agent] = date
      errors[agent] = nil
      if let window = report.window, window.isValid {
        var samples = history[agent] ?? []
        samples.append(QuotaSample(date: date, remaining: 100 - window.usedPercent))
        history[agent] = Array(
          samples.filter { $0.date > date.addingTimeInterval(-35 * 86400) }.suffix(12_000))
        saveHistory()
      }
    } catch { errors[agent] = error.localizedDescription }
  }

  func changePeriod() async {
    summary =
      archive.agents.isEmpty
      ? cache?.summaries[period.rawValue]?.report
      : archive.report(period: period, live: cache?.summaries[period.rawValue]?.report)
    updated["summary"] = cache?.summaries[period.rawValue]?.date
    await refresh()
  }

  private func saveCache() {
    do {
      try FileManager.default.createDirectory(
        at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      if let cache { try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic) }
      errors["cache"] = nil
    } catch { errors["cache"] = "Unable to save report history on this Mac." }
  }

  func forecast(for agent: String) -> Forecast? {
    guard let window = reports[agent]?.window, window.isValid, let date = updated[agent] else {
      return nil
    }
    return Forecast(window: window, observedAt: date)
  }

  func samples(for agent: String) -> [QuotaSample] {
    guard let forecast = forecast(for: agent) else { return [] }
    return cycleSamples(history[agent] ?? [], since: forecast.start.addingTimeInterval(-60))
  }

  private func saveHistory() {
    do {
      try FileManager.default.createDirectory(
        at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
    } catch {
      // Reports remain usable if local history cannot be saved.
      errors["history"] =
        "Quota history could not be saved. Check access to Application Support/Agent Burn."
    }
  }
}

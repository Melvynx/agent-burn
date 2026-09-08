import SwiftUI

enum UsagePeriod: String, CaseIterable, Identifiable {
  case today, yesterday, rtd, wtd, mtd, week, month, ytd, all
  var id: String { rawValue }
  var arguments: [String] {
    ["summary"] + (self == .all || self == .rtd ? [] : [rawValue]) + ["--value"]
  }
  var label: String {
    switch self {
    case .today: "Today"
    case .all: "All time"
    case .yesterday: "Yesterday"
    case .rtd: "Reset to date"
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
  var isLoading: Bool { isRefreshing || summaryTask != nil }
  private var isRefreshing = false
  private var summaryTask: Task<Void, Never>?
  private var pendingSummary: (query: SummaryQuery, force: Bool)?
  private var pendingHistory: SummaryQuery?
  private var summaryErrors: [String: String] = [:]
  private var currentQuery: SummaryQuery {
    SummaryQuery(
      period: period == .rtd ? .all : period,
      agent: selection == "summary" ? nil : selection)
  }
  var hasPeriodDetails: Bool { savedSummary(for: currentQuery) != nil }
  var period = UsagePeriod.mtd {
    didSet {
      guard oldValue != period else { return }
      changePeriod()
    }
  }
  var selection = "summary" {
    didSet {
      guard oldValue != selection else { return }
      changePeriod()
    }
  }
  var customPath: String { didSet { defaults.set(customPath, forKey: "cliPath") } }
  var codexHomes: String { didSet { defaults.set(codexHomes, forKey: "codexHomes") } }
  var offline: Bool { didSet { defaults.set(offline, forKey: "offline") } }
  var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: "refreshMinutes") } }
  var quotaSource: QuotaSource {
    didSet { defaults.set(quotaSource.rawValue, forKey: "quotaSource") }
  }
  var quotaChartRange: QuotaChartRange {
    didSet { defaults.set(quotaChartRange.rawValue, forKey: "quotaChartRange") }
  }
  private var history: [String: [QuotaSample]] = [:]
  private var quotaHistory = QuotaHistory()
  private var quotaSourceKey: String { customPath + "|" + codexHomes }
  private var quotaFileDate: Date?
  private var configuredQuotaSource: String?
  private var collectedQuotaSource: String?
  private var quotaCollectionDate: Date?
  private var isCollectingQuotas = false
  var quotaCheckDate = Date.now
  private let defaults: UserDefaults
  private let historyURL: URL
  private let cacheURL: URL
  private var cache: ReportCache?
  private var archive = MetricsArchive()
  private var archiveWritable = true
  var archiveURL: URL {
    cacheURL.deletingLastPathComponent().appendingPathComponent("metrics-history.json")
  }
  var recoveredCursor: AgentUsage? {
    cache?.summaries["cursor-recovered"]?.report.agents.first { $0.agent == "cursor" }
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
    refreshMinutes = max(1, defaults.integer(forKey: "refreshMinutes"))
    quotaSource = QuotaSource(rawValue: defaults.string(forKey: "quotaSource") ?? "") ?? .codex
    quotaChartRange =
      QuotaChartRange(rawValue: defaults.string(forKey: "quotaChartRange") ?? "") ?? .rte
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
    if let decoded = try? ReportCacheFile(directory: cacheURL.deletingLastPathComponent())
      .load(source: sourceKey)
    {
      cache = decoded
      summary = decoded.summaries[period.rawValue]?.report ?? decoded.summaries["all"]?.report
      updated["summary"] =
        decoded.summaries[period.rawValue]?.date
        ?? decoded.summaries["all"]?.date
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
        summary = archive.report(period: period, live: summary, resetStart: resetStartDate)
      }
    } catch {
      archiveWritable = false
      errors["archive"] =
        "Metrics history could not be read or saved. Existing files have been preserved."
    }
    reloadQuotas()
    publishSummary()
  }

  func reloadQuotas() {
    do {
      let file = QuotaHistoryFile(directory: cacheURL.deletingLastPathComponent())
      let date = try? file.url.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      if let date, date == quotaFileDate { return }
      if let saved = try file.load() {
        quotaHistory = saved
      }
      quotaFileDate = date
      errors["quotaHistory"] = nil
    } catch {
      errors["quotaHistory"] =
        "Quota history could not be read. The last available readings are preserved."
    }
  }

  func start() async {
    guard !started else { return }
    started = true
    configureQuotaCollector()
    if defaults.object(forKey: "backgroundQuotas") as? Bool != false {
      do { try await QuotaService.registerForCurrentBundle() } catch {
        errors["quotaService"] =
          "Background collection could not start. Enable it in Settings → Background quota history."
      }
    }
    async let quotas: () = watchQuotas()
    async let reports: () = refreshReports()
    _ = await (quotas, reports)
    started = false
  }

  private func configureQuotaCollector() {
    guard configuredQuotaSource != quotaSourceKey else { return }
    do {
      try QuotaCollectorConfig(customPath: customPath, codexHomes: codexHomes)
        .save(directory: cacheURL.deletingLastPathComponent())
      configuredQuotaSource = quotaSourceKey
      errors["quotaConfig"] = nil
    } catch {
      errors["quotaConfig"] = "Background quota settings could not be saved."
    }
  }

  private func watchQuotas() async {
    while !Task.isCancelled {
      quotaCheckDate = .now
      configureQuotaCollector()
      reloadQuotas()
      let backgroundEnabled = defaults.object(forKey: "backgroundQuotas") as? Bool != false
      let status = QuotaService.service.status
      if status == .enabled {
        errors["quotaService"] = nil
      } else if backgroundEnabled {
        errors["quotaService"] =
          status == .requiresApproval
          ? "Allow Agent Burn background activity in System Settings. Quotas are collected while this app is open."
          : "Background collection is unavailable. Enable it in Settings to continue collecting after quitting."
      } else {
        errors["quotaService"] = nil
      }
      let sourceChanged = collectedQuotaSource != quotaSourceKey
      let retryDue = Date.now.timeIntervalSince(quotaCollectionDate ?? .distantPast) >= 60
      if sourceChanged || (status != .enabled && retryDue) {
        await collectQuotasNow()
      }
      try? await Task.sleep(for: .seconds(5))
    }
  }

  func collectQuotasNow() async {
    guard !isCollectingQuotas else { return }
    isCollectingQuotas = true
    defer { isCollectingQuotas = false }
    configureQuotaCollector()
    collectedQuotaSource = quotaSourceKey
    quotaCollectionDate = .now
    do {
      try await QuotaCollector.collect(directory: cacheURL.deletingLastPathComponent())
      errors["quotaCollector"] = nil
    } catch {
      errors["quotaCollector"] =
        "Quota collection could not save its readings. Existing history is preserved."
    }
    reloadQuotas()
  }

  private func refreshReports() async {
    await refresh()
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(refreshMinutes * 60))
      if !Task.isCancelled { await refresh() }
    }
  }

  func quotaError(for agent: String) -> String? {
    errors["quotaHistory"] ?? errors["quotaConfig"] ?? errors["quotaCollector"]
      ?? quotaHistory.failures[quotaSourceKey]?[agent]
  }

  func refreshAll() async {
    async let quotas: () = collectQuotasNow()
    await refresh()
    await quotas
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    queueSummary(force: true, includeHistory: true)
    let summaries = summaryTask
    let selectedAgent = currentQuery.agent
    do {
      let executable = try CLIClient.executable(customPath: customPath)
      let useOffline = offline
      // Quota collection is independent; these reports provide spend details.
      await withTaskGroup(of: Void.self) { group in
        for agent in ["codex", "claude"] where selectedAgent == nil || selectedAgent == agent {
          group.addTask {
            await self.loadHarness(agent, executable: executable, offline: useOffline)
          }
        }
      }
    } catch {
      for agent in ["codex", "claude"] where selectedAgent == nil || selectedAgent == agent {
        errors[agent] = error.localizedDescription
      }
    }
    await summaries?.value
  }

  private func savedSummary(for query: SummaryQuery) -> CachedReport<SummaryReport>? {
    guard cache?.source == sourceKey else { return nil }
    // An all-harness report can satisfy a focused request, never the reverse.
    return [cache?.summaries[query.cacheKey], cache?.summaries[query.period.rawValue]]
      .compactMap { $0 }.max { $0.date < $1.date }
  }

  private func isFresh(_ query: SummaryQuery, interval: TimeInterval? = nil) -> Bool {
    guard let saved = savedSummary(for: query) else { return false }
    return Calendar.current.isDateInToday(saved.date)
      && Date.now.timeIntervalSince(saved.date) < (interval ?? Double(refreshMinutes * 60))
  }

  private func publishSummary() {
    let saved = savedSummary(for: currentQuery)
    summary =
      archive.agents.isEmpty
      ? saved?.report
      : archive.report(period: period, live: saved?.report, resetStart: resetStartDate)
    // Account allowance is independent of the selected historical date range.
    summary?.cursorAccount =
      cache?.summaries.values.sorted { $0.date > $1.date }
      .compactMap { $0.report.cursorAccount }.first
    updated["summary"] = saved?.date
    errors["summary"] = summaryErrors[currentQuery.cacheKey]
  }

  private func queueSummary(force: Bool = false, includeHistory: Bool = false) {
    if cache?.source != sourceKey {
      cache = ReportCache(source: sourceKey, summaries: [:], harnesses: [:])
      reports = [:]
      updated = [:]
      summaryErrors = [:]
      publishSummary()
    }
    let query = currentQuery
    pendingSummary = force || !isFresh(query) ? (query, force) : nil
    if pendingHistory?.agent != query.agent { pendingHistory = nil }
    if includeHistory, query.period != .all {
      let history = SummaryQuery(period: .all, agent: query.agent)
      // Historic days need a daily backfill, not a rescan on every picker change.
      if !isFresh(history, interval: 86400) { pendingHistory = history }
    }
    guard summaryTask == nil, pendingSummary != nil || pendingHistory != nil else { return }
    summaryTask = Task {
      defer { summaryTask = nil }
      while pendingSummary != nil || pendingHistory != nil {
        // Coalesce quick selections before starting another expensive process.
        try? await Task.sleep(for: .milliseconds(200))
        if let pending = pendingSummary {
          pendingSummary = nil
          if pending.force || !isFresh(pending.query) { await loadSummary(pending.query) }
        } else if let history = pendingHistory {
          pendingHistory = nil
          if !isFresh(history, interval: 86400) { await loadSummary(history) }
        }
      }
    }
  }

  private func loadSummary(_ query: SummaryQuery) async {
    let source = sourceKey
    do {
      let executable = try CLIClient.executable(customPath: customPath)
      let report = try await CLIClient.read(
        SummaryReport.self, executable: executable,
        arguments: query.arguments, offline: offline, environment: ["CODEX_HOME": codexHomes])
      guard source == sourceKey else { return }
      cache?.summaries[query.cacheKey] = CachedReport(report: report, date: .now)
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
      summaryErrors[query.cacheKey] = nil
      publishSummary()
    } catch {
      guard source == sourceKey else { return }
      summaryErrors[query.cacheKey] = error.localizedDescription
      if query == currentQuery { errors["summary"] = error.localizedDescription }
    }
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
    } catch { errors[agent] = error.localizedDescription }
  }

  func changePeriod() {
    publishSummary()
    queueSummary()
  }

  private func saveCache() {
    do {
      if let cache {
        try ReportCacheFile(directory: cacheURL.deletingLastPathComponent()).save(cache)
      }
      errors["cache"] = nil
    } catch { errors["cache"] = "Unable to save report history on this Mac." }
  }

  var remainingPercent: Double? {
    remainingQuota(
      for: quotaSource, forecast: forecast(for: quotaSource.rawValue),
      cursorAccount: summary?.cursorAccount)
  }

  func forecast(for agent: String) -> Forecast? {
    if let reading = quotaHistory.latest(agent: agent, source: quotaSourceKey) {
      return Forecast(window: reading.window, observedAt: reading.date, isLive: true)
    }
    guard let window = reports[agent]?.window, window.isValid, let date = updated[agent] else {
      return nil
    }
    return Forecast(window: window, observedAt: date)
  }

  func archivedSamples(for agent: String) -> [QuotaSample] {
    quotaHistory.latest(agent: agent, source: quotaSourceKey) == nil
      ? history[agent] ?? [] : quotaHistory.samples(agent: agent, source: quotaSourceKey)
  }

  func samples(for agent: String, range: QuotaChartRange = .rte, now: Date = .now) -> [QuotaSample]
  {
    guard let forecast = forecast(for: agent) else { return [] }
    return quotaChartSamples(
      archivedSamples(for: agent), range: range, forecast: forecast, now: now)
  }

  func resets(for agent: String) -> [QuotaReset] {
    quotaHistory.resets(agent: agent, source: quotaSourceKey)
  }

  var resetStartDate: Date? {
    let agent = selection == "summary" ? quotaSource.rawValue : selection
    return resets(for: agent).last?.date ?? forecast(for: agent)?.start
  }

}

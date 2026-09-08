import SwiftUI
import Testing

@testable import AgentBurn

// Opt-in acceptance proof against the installed collector's real provider readings.
@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_BURN_QUOTA_PROOF_DIR"] != nil))
@MainActor func liveQuotaArchiveDrivesTheDisplayedPercentageAndChart() throws {
  let output = URL(
    fileURLWithPath: try #require(
      ProcessInfo.processInfo.environment["AGENT_BURN_QUOTA_PROOF_DIR"]))
  let input = QuotaCollectorConfig.directory
  let config = try JSONDecoder().decode(
    QuotaCollectorConfig.self,
    from: Data(contentsOf: input.appendingPathComponent("quota-collector.json")))
  let liveHistory = try #require(try QuotaHistoryFile(directory: input).load())
  let reading = try #require(liveHistory.latest(agent: "codex", source: config.source))
  #expect(abs(reading.date.timeIntervalSinceNow) < 90)
  let suite = "AgentBurn.live-proof.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(config.customPath, forKey: "cliPath")
  defaults.set(config.codexHomes, forKey: "codexHomes")
  let storage = output.appendingPathComponent(UUID().uuidString)
  try QuotaHistoryFile(directory: storage).save(liveHistory)
  let store = UsageStore(defaults: defaults, storageDirectory: storage)
  let forecast = try #require(store.forecast(for: "codex"))
  #expect(forecast.isFresh(at: .now))
  #expect(!store.quotaIsStale(at: .now))
  #expect(store.remainingPercent == 100 - reading.window.usedPercent)
  #expect(store.samples(for: "codex").last?.remaining == store.remainingPercent)
  let proof =
    "Measured: \(reading.date)\nRemaining: \(try #require(store.remainingPercent))%\nMenu: \(menuBarQuotaText(store.remainingPercent))\nSamples: \(store.samples(for: "codex").count)\n"
  try Data(proof.utf8).write(to: output.appendingPathComponent("live-quota-proof.txt"))
  _ = NSApplication.shared
  let view = VStack(alignment: .leading, spacing: 18) {
    Text("Codex weekly quota").font(.title2.bold())
    Text(menuBarQuotaText(store.remainingPercent)).font(.system(size: 48, weight: .semibold))
    QuotaFreshnessView(forecast: forecast, error: store.quotaError(for: "codex"))
    QuotaChart(forecast: forecast, samples: store.samples(for: "codex"), color: .green)
  }.padding(24).frame(width: 850).background(BurnTheme.background)
  let renderer = ImageRenderer(content: view)
  renderer.scale = 2
  let cgImage = try #require(renderer.cgImage)
  let bitmap = NSBitmapImageRep(cgImage: cgImage)
  let png = try #require(bitmap.representation(using: .png, properties: [:]))
  try png.write(to: output.appendingPathComponent("live-quota.png"))
}

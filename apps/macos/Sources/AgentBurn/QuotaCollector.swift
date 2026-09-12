import Darwin
import Foundation

struct QuotaCollectorConfig: Codable, Sendable {
  let customPath: String
  let codexHomes: String
  var source: String { customPath + "|" + codexHomes }
  static var directory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Agent Burn")
  }

  func save(directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(self).write(
      to: directory.appendingPathComponent("quota-collector.json"), options: .atomic)
  }
}

private struct CollectedQuota: Codable, Sendable {
  let agent: String
  let observedAt: Double
  let window: QuotaWindow?
}

enum QuotaCollector {
  /// launchd owns scheduling; this process performs one bounded collection and exits.
  static func collect(directory: URL = QuotaCollectorConfig.directory) async throws {
    let config = try JSONDecoder().decode(
      QuotaCollectorConfig.self,
      from: Data(contentsOf: directory.appendingPathComponent("quota-collector.json")))
    // Also protect manual invocations and app upgrades from overlapping writes.
    let descriptor = open(
      directory.appendingPathComponent("quota-collector.lock").path,
      O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return }
    defer { flock(descriptor, LOCK_UN) }
    let file = QuotaHistoryFile(directory: directory)
    var history = try file.load() ?? QuotaHistory()
    await withTaskGroup(of: (String, QuotaReading?, String?).self) { group in
      for agent in ["codex", "claude"] {
        group.addTask {
          do {
            let executable = try CLIClient.executable(customPath: config.customPath)
            let reading = try await CLIClient.read(
              QuotaReading.self,
              executable: executable, arguments: ["harness", agent], offline: false,
              environment: ["CODEX_HOME": config.codexHomes, "AGENT_BURN_QUOTA_ONLY": "1"],
              timeout: 45)
            guard reading.agent == agent, reading.observedAt.isFinite, reading.window.isValid,
              abs(reading.date.timeIntervalSinceNow) <= 90
            else { throw CLIError.invalidOutput }
            return (agent, reading, nil)
          } catch {
            return (agent, nil, "Live quota could not be collected. The last reading is preserved.")
          }
        }
      }
      group.addTask {
        do {
          let executable = try CLIClient.executable(customPath: config.customPath)
          let collected = try await CLIClient.read(
            CollectedQuota.self,
            executable: executable, arguments: ["summary", "--value"], offline: false,
            environment: ["CODEX_HOME": config.codexHomes, "AGENT_BURN_QUOTA_ONLY": "1"],
            timeout: 45)
          guard collected.agent == "cursor", collected.observedAt.isFinite,
            abs(Date(timeIntervalSince1970: collected.observedAt / 1000).timeIntervalSinceNow)
              <= 90
          else { throw CLIError.invalidOutput }
          guard let window = collected.window, window.isValid else {
            return ("cursor", nil, nil)
          }
          return (
            "cursor",
            QuotaReading(
              agent: "cursor", observedAt: collected.observedAt, window: window),
            nil
          )
        } catch {
          return (
            "cursor", nil,
            "Live Cursor credits could not be collected. The last reading is preserved."
          )
        }
      }
      for await (agent, reading, error) in group {
        if let reading { history.record(reading, source: config.source) }
        if let error {
          history.fail(agent: agent, source: config.source, message: error)
        } else if reading == nil {
          history.failures[config.source]?[agent] = nil
        }
        // Persist each provider immediately, even if the other hangs or this process crashes.
        do { try file.save(history) } catch {
          FileHandle.standardError.write(Data("Quota history could not be saved.\n".utf8))
        }
      }
    }
    try file.save(history)
  }
}

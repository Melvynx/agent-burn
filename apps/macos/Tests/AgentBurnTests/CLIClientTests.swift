import Foundation
import Testing

@testable import AgentBurn

@Test func readsNativeJSONFromExecutableWithSpaces() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let executable = directory.appendingPathComponent("agent burn fixture")
  try Data(
    """
    #!/bin/sh
    [ "$1" = "summary" ] && [ "$2" = "week" ] && [ "$3" = "--json" ] && [ "$5" = "--offline" ] || exit 3
    printf '%s' '{"totals":{"totalCost":12.5,"totalTokens":500},"agents":[],"models":[]}'
    """.utf8
  ).write(to: executable)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
  let result = try await CLIClient.read(
    SummaryReport.self, executable: executable, arguments: ["summary", "week"], offline: true)
  #expect(result.totals.totalCost == 12.5)
  #expect(result.totals.totalTokens == 500)
}

@Test func failedCLIReportsAnErrorInsteadOfEmptyUsage() async {
  await #expect(throws: CLIError.self) {
    try await CLIClient.read(
      SummaryReport.self, executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [],
      offline: false)
  }
}

@Test func passesSelectedLogHomesToTheChildProcess() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let executable = directory.appendingPathComponent("fixture")
  try Data(
    """
    #!/bin/sh
    [ "$CODEX_HOME" = "/normal/.codex,/extra profile" ] || exit 7
    printf '%s' '{"totals":{"totalCost":99,"totalTokens":100},"agents":[],"models":[]}'
    """.utf8
  ).write(to: executable)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
  let report = try await CLIClient.read(
    SummaryReport.self, executable: executable, arguments: [], offline: true,
    environment: ["CODEX_HOME": "/normal/.codex,/extra profile"])
  #expect(report.totals.totalCost == 99)
}

@Test func invalidJSONReportsAnErrorInsteadOfEmptyUsage() async {
  await #expect(throws: CLIError.self) {
    try await CLIClient.read(
      SummaryReport.self, executable: URL(fileURLWithPath: "/usr/bin/printf"),
      arguments: ["invalid"], offline: false)
  }
}

@Test func explicitMissingExecutableDoesNotSilentlyUseAnotherCLI() {
  #expect(throws: CLIError.self) {
    try CLIClient.executable(customPath: "/nonexistent/agent-burn")
  }
}

@Test func exhaustedQuotaPredictsNoDailyAllowance() {
  let forecast = Forecast(
    window: QuotaWindow(
      windowMinutes: 10080, usedPercent: 100, elapsedPercent: 80, apiEquivalentSpent: 400),
    observedAt: .now)
  #expect(forecast.remaining == 0)
  #expect(forecast.dailyAllowance == 0)
  #expect(forecast.projectedEnd <= forecast.observedAt)
}

@Test func invalidProviderWindowIsNotEligibleForForecasting() {
  #expect(
    !QuotaWindow(windowMinutes: 0, usedPercent: 50, elapsedPercent: 40, apiEquivalentSpent: 0)
      .isValid)
  #expect(
    !QuotaWindow(windowMinutes: 10080, usedPercent: -1, elapsedPercent: 40, apiEquivalentSpent: 0)
      .isValid)
}

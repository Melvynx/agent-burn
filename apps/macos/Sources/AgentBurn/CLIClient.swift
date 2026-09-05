import Foundation

enum CLIError: LocalizedError {
  case missing
  case failed(Int32)
  case timedOut, invalidOutput
  var errorDescription: String? {
    switch self {
    case .missing: "Agent Burn CLI not found. Choose the native agent-burn executable in Settings."
    case .failed(let code):
      "Agent Burn exited with status \(code). Check your CLI configuration and harness sign-in, then retry."
    case .timedOut:
      "The CLI took longer than two minutes. Try cached pricing in Settings, then refresh."
    case .invalidOutput:
      "The CLI returned an unsupported report. Rebuild the app with the current Agent Burn CLI."
    }
  }
}

enum CLIClient {
  static func executable(customPath: String) throws -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let candidates =
      customPath.isEmpty
      ? [
        Bundle.main.resourceURL?.appendingPathComponent("agent-burn").path ?? "",
        "/opt/homebrew/bin/agent-burn", "/usr/local/bin/agent-burn",
        "\(home)/.local/bin/agent-burn", "\(home)/.cargo/bin/agent-burn",
      ] : [NSString(string: customPath).expandingTildeInPath]
    guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    else {
      throw CLIError.missing
    }
    return URL(fileURLWithPath: path)
  }

  static func read<T: Decodable & Sendable>(
    _ type: T.Type, executable: URL, arguments: [String], offline: Bool,
    environment: [String: String] = [:]
  ) async throws -> T {
    try await Task.detached(priority: .utility) {
      let data = try run(
        executable: executable,
        arguments: arguments + ["--json", "--no-color"] + (offline ? ["--offline"] : []),
        environment: environment)
      do { return try JSONDecoder().decode(type, from: data) } catch {
        throw CLIError.invalidOutput
      }
    }.value
  }

  private static func run(executable: URL, arguments: [String], environment: [String: String])
    throws -> Data
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("output.json")
    FileManager.default.createFile(
      atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
    let handle = try FileHandle(forWritingTo: output)
    defer { try? handle.close() }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in
      override
    }
    process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    process.standardOutput = handle
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()
    let deadline = Date().addingTimeInterval(120)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    if process.isRunning {
      process.terminate()
      Thread.sleep(forTimeInterval: 0.2)
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      process.waitUntilExit()
      throw CLIError.timedOut
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CLIError.failed(process.terminationStatus) }
    let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 16_000_000 else { throw CLIError.invalidOutput }
    return try Data(contentsOf: output)
  }
}

import Darwin
import Foundation

@main
enum AgentBurnQuotaCollectorMain {
  static func main() async {
    do {
      try await QuotaCollector.collect()
    } catch {
      FileHandle.standardError.write(
        Data("Quota collection failed: \(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }
}

import Foundation

enum SourcePaths {
  static func codexHomes(home: String, inherited: String?) -> String {
    let candidates = [home + "/.codex"] + (inherited ?? "").split(separator: ",").map(String.init)
    var paths: [String] = []
    for candidate in candidates {
      let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let path = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
        .standardizedFileURL.resolvingSymlinksInPath().path
      if !paths.contains(path) { paths.append(path) }
    }
    return paths.joined(separator: ",")
  }
}

struct CachedReport<Report: Codable>: Codable {
  let report: Report
  let date: Date
}

struct ReportCache: Codable {
  let source: String
  var summaries: [String: CachedReport<SummaryReport>]
  var harnesses: [String: CachedReport<HarnessReport>]
  var agentNames: [String] {
    Set(summaries.values.flatMap { $0.report.agents.map(\.agent) }).sorted()
  }
}

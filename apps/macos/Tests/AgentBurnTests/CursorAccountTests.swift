import Foundation
import Testing

@testable import AgentBurn

@Test func cursorAccountSurvivesArchivalProjection() throws {
  let report = try JSONDecoder().decode(
    SummaryReport.self,
    from: Data(
      """
      {"totals":{"totalCost":0,"totalTokens":0},"agents":[],"models":[],"cursorAccount":{"includedLimitUSD":400,"includedRemainingUSD":400,"includedPercentUsed":0,"billingCycleEndMs":1790483947000,"grants":[{"kind":"promo","totalUSD":9905.27,"remainingUSD":9130.20,"expiresAtMs":1819945202627}]}}
      """.utf8))
  let projected = MetricsArchive().report(period: .all, live: report)
  #expect(projected.cursorAccount?.includedLimitUSD == 400)
  #expect(projected.cursorAccount?.grants.first?.remainingUSD == 9130.20)
  #expect(projected.cursorAccount?.onDemandLimitUSD == nil)
}

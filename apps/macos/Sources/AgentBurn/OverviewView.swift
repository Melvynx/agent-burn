import SwiftUI

struct OverviewView: View {
  @Environment(UsageStore.self) private var store
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 20 : 28) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 6) {
          Text(compact ? "All your harnesses" : "Usage at a glance")
            .font(.system(size: compact ? 21 : 28, weight: .semibold))
          Text("One place for every agent.").font(.system(size: 13)).foregroundStyle(
            BurnTheme.muted)
        }
        Spacer()
        PeriodPicker()
      }
      if let error = store.errors["summary"] { ReportNotice(message: error) }
      if let report = store.summary {
        HStack(spacing: 0) {
          metric("API-equivalent usage", value: currency(report.totals.totalCost))
          if !compact {
            Rectangle().fill(BurnTheme.line).frame(width: 1, height: 44).padding(.horizontal, 28)
          } else {
            Spacer()
          }
          metric("Tokens processed", value: tokens(report.totals.totalTokens))
          if !compact {
            Rectangle().fill(BurnTheme.line).frame(width: 1, height: 44).padding(.horizontal, 28)
            metric("Active harnesses", value: String(report.agents.count))
          }
        }
        .padding(.vertical, compact ? 8 : 18)
        if !compact, let daily = report.daily, !daily.isEmpty {
          DailySpendChart(title: "Daily usage", days: daily)
        }
        VStack(alignment: .leading, spacing: 18) {
          SectionLabel(title: "Usage by harness", detail: store.period.label)
          if report.agents.isEmpty {
            ReportNotice(
              message:
                "No local usage in this period. Run an agent session or choose a longer date range."
            )
          }
          ForEach(report.agents) { agent in
            agentRow(agent, totals: report.totals)
          }
        }
        if !report.models.isEmpty {
          Rectangle().fill(BurnTheme.line).frame(height: 1)
          VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Model breakdown", detail: "\(report.models.count) models")
              .padding(.bottom, 18)
            ForEach(Array(report.models.prefix(compact ? 3 : report.models.count))) { model in
              HStack(spacing: 14) {
                Text(model.model).lineLimit(1).help(model.model).frame(
                  maxWidth: .infinity, alignment: .leading)
                Text(tokens(model.totalTokens)).foregroundStyle(BurnTheme.muted).frame(
                  width: 68, alignment: .trailing)
                Text(currency(model.totalCost)).frame(width: 90, alignment: .trailing)
              }
              .font(.system(size: 12)).monospacedDigit().padding(.vertical, 12)
              Rectangle().fill(BurnTheme.line).frame(height: 1)
            }
          }
        }
        if !compact, let subscription = report.subscription, !subscription.agents.isEmpty {
          VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Subscriptions", detail: "Monthly plan prices")
            ForEach(subscription.agents) { agent in
              HStack {
                Text(harnessName(agent.agent))
                Text(agent.plan ?? "Unknown plan").foregroundStyle(BurnTheme.muted)
                Spacer()
                Text(agent.pricePerMonth.map(currency) ?? "Price unavailable")
              }.font(.system(size: 12))
            }
          }
        }
        Label(
          "API-equivalent usage estimates token value, not your subscription bill.",
          systemImage: "info.circle"
        )
        .font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
      } else {
        VStack(alignment: .leading, spacing: 12) {
          Text(store.isLoading ? "Gathering your local usage…" : "Connect your usage")
            .font(.system(size: 20, weight: .medium))
          Text(
            "Agent Burn reads the same local harness logs as the CLI. Choose the executable in Settings if it isn't detected automatically."
          )
          .font(.system(size: 13)).foregroundStyle(BurnTheme.muted)
        }.frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
      }
    }
  }

  private func metric(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(label).font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
      Text(value).font(.system(size: compact ? 25 : 32, weight: .medium, design: .rounded))
        .monospacedDigit()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func agentRow(_ agent: AgentUsage, totals: Totals) -> some View {
    let share =
      totals.totalCost > 0
      ? agent.totalCost / totals.totalCost
      : totals.totalTokens > 0 ? Double(agent.totalTokens) / Double(totals.totalTokens) : 0
    return HStack(spacing: 12) {
      HarnessIcon(agent: agent.agent, size: compact ? 30 : 38)
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(harnessName(agent.agent)).font(.system(size: 13, weight: .medium))
          Spacer()
          Text(tokens(agent.totalTokens)).font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
          Text(currency(agent.totalCost)).font(.system(size: 13, weight: .medium)).frame(
            width: 85, alignment: .trailing)
        }
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            Capsule().fill(BurnTheme.elevated)
            Capsule().fill(BurnTheme.color(for: agent.agent)).frame(
              width: geometry.size.width * max(0, min(1, share)))
          }
        }.frame(height: 4).accessibilityLabel(
          "\(Int(share * 100)) percent of \(totals.totalCost > 0 ? "usage value" : "tokens")")
      }
    }.monospacedDigit().padding(.vertical, 5)
  }
}

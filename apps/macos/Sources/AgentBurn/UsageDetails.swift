import Charts
import SwiftUI

struct SpendMetric: View {
  let title: String
  let value: String
  var detail = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
      Text(value).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
      if !detail.isEmpty { Text(detail).font(.system(size: 10)).foregroundStyle(BurnTheme.muted) }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct DailySpendChart: View {
  let title: String
  let days: [DailyUsage]
  var color = BurnTheme.accent
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SectionLabel(title: title, detail: "API-equivalent USD")
      Chart(days) { day in
        BarMark(x: .value("Date", day.date), y: .value("Usage", day.cost))
          .foregroundStyle(color).cornerRadius(3)
          .accessibilityLabel(day.date).accessibilityValue(currency(day.cost))
      }
      .chartYAxis {
        AxisMarks(position: .leading) { _ in
          AxisGridLine().foregroundStyle(BurnTheme.line)
          AxisValueLabel().foregroundStyle(BurnTheme.muted)
        }
      }
      .chartXAxis {
        AxisMarks(
          values: Array(
            days.enumerated().filter { $0.offset % max(1, days.count / 7) == 0 }.map {
              $0.element.date
            })
        ) { value in
          AxisValueLabel {
            if let date = value.as(String.self) {
              Text(String(date.suffix(5))).foregroundStyle(BurnTheme.muted)
            }
          }
        }
      }
      .frame(height: 150)
    }
  }
}

struct HarnessSpendDetails: View {
  let report: HarnessReport
  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      if !report.daily.isEmpty {
        DailySpendChart(
          title: "Daily usage · current cycle", days: report.daily,
          color: BurnTheme.color(for: report.agent))
      }
      if let mix = report.spendMix, !mix.isEmpty {
        VStack(alignment: .leading, spacing: 14) {
          SectionLabel(title: "Spend by token type", detail: "Past 30 days")
          ForEach(mix) { category in
            HStack {
              Text(category.label.capitalized).frame(maxWidth: .infinity, alignment: .leading)
              Text(tokens(category.tokens)).foregroundStyle(BurnTheme.muted).frame(
                width: 85, alignment: .trailing)
              Text("\(category.costPercent.formatted(.number.precision(.fractionLength(1))))%")
                .foregroundStyle(BurnTheme.muted).frame(width: 60, alignment: .trailing)
              Text(currency(category.costUSD)).frame(width: 90, alignment: .trailing)
            }.font(.system(size: 12)).monospacedDigit()
          }
        }
      }
      if let trend = report.weeklyTrend, !trend.isEmpty {
        DailySpendChart(
          title: "Weekly trend", days: trend.map { DailyUsage(date: $0.weekStart, cost: $0.cost) },
          color: BurnTheme.color(for: report.agent))
      }
      if let estimate = report.estimate {
        VStack(alignment: .leading, spacing: 14) {
          SectionLabel(title: "Quota value estimate", detail: "Based on current cycle")
          detail("Full quota value", currency(estimate.fullQuotaValue))
          detail("Monthly quota value", currency(estimate.monthlyValue))
          detail(
            "Projected quota consumption",
            "\(estimate.projectedUsePercent.formatted(.number.precision(.fractionLength(0))))%")
          if let multiple = estimate.valueMultiple {
            detail(
              "Quota value / plan price",
              "\(multiple.formatted(.number.precision(.fractionLength(1))))×")
          }
        }
      }
      if let images = report.imageGenerations, report.agent == "codex" {
        VStack(alignment: .leading, spacing: 14) {
          SectionLabel(title: "Image generations", detail: "Past 30 days")
          detail("Generated images", images.count.formatted())
          detail("Estimated image cost", currency(images.estimatedCost))
          Text(
            "\(currency(images.pricePerImageEstimate)) per image estimate. Separate from token usage."
          )
          .font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
        }
      }
    }
  }

  private func detail(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).foregroundStyle(BurnTheme.muted)
      Spacer()
      Text(value)
    }
    .font(.system(size: 12)).monospacedDigit()
  }
}

struct SourceUsageView: View {
  @Environment(UsageStore.self) private var store
  let agent: String
  var compact = false
  private var usage: AgentUsage? { store.summary?.agents.first { $0.agent == agent } }
  private var subscription: SubscriptionAgent? {
    store.summary?.subscription?.agents.first { $0.agent == agent }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      HStack(spacing: 10) {
        HarnessIcon(agent: agent)
        VStack(alignment: .leading, spacing: 4) {
          Text(harnessName(agent)).font(.system(size: 23, weight: .semibold))
          Text(subscription?.plan ?? "Harness usage").font(.system(size: 12)).foregroundStyle(
            BurnTheme.muted)
        }
        Spacer()
        PeriodPicker()
      }
      if let error = store.errors["summary"] { ReportNotice(message: error) }
      if let usage {
        HStack {
          SpendMetric(
            title: "Total spend", value: currency(usage.totalCost),
            detail: store.period.label + " · API-equivalent")
          SpendMetric(title: "Total tokens", value: tokens(usage.totalTokens))
          if !compact, let price = subscription?.pricePerMonth {
            SpendMetric(
              title: "Monthly plan", value: currency(price), detail: subscription?.plan ?? "")
          }
        }
        if agent == "cursor" {
          CursorAccountView(account: store.summary?.cursorAccount, plan: subscription)
        } else {
          ReportNotice(message: "Subscription limits are not available for this harness.")
        }
        if let daily = usage.daily, !daily.isEmpty {
          DailySpendChart(title: "Daily usage", days: daily, color: BurnTheme.color(for: agent))
        }
        if let models = usage.models, !models.isEmpty {
          VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Model breakdown", detail: store.period.label)
            ForEach(Array(models.prefix(compact ? 3 : models.count))) { model in
              HStack {
                Text(model.model).lineLimit(1).help(model.model)
                Spacer()
                Text(tokens(model.totalTokens)).foregroundStyle(BurnTheme.muted)
                Text(currency(model.totalCost)).frame(width: 90, alignment: .trailing)
              }.font(.system(size: 12)).monospacedDigit()
            }
          }
        }
        if !compact, let breakdown = usage.tokenBreakdown {
          VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Token breakdown", detail: store.period.label)
            ForEach(
              [
                ("input", "Input"), ("output", "Output"), ("cacheWrite", "Cache write"),
                ("cacheRead", "Cache read"),
              ], id: \.0
            ) { key, label in
              HStack {
                Text(label).foregroundStyle(BurnTheme.muted)
                Spacer()
                Text(tokens(breakdown[key] ?? 0))
              }
              .font(.system(size: 12)).monospacedDigit()
            }
          }
        }
      } else {
        ReportNotice(
          message: store.isLoading
            ? "Reading harness usage…"
            : agent == "cursor" && store.offline
              ? "Cursor usage requires its dashboard connection. Turn off cached mode in Settings to load it."
              : "No usage found for this period. Choose a longer range and check that the harness is signed in."
        )
      }
    }
  }
}

struct PeriodPicker: View {
  @Environment(UsageStore.self) private var store
  var body: some View {
    @Bindable var store = store
    Picker("Period", selection: $store.period) {
      ForEach(UsagePeriod.allCases) { period in Text(period.label).tag(period) }
    }.labelsHidden().frame(width: 145).disabled(store.isLoading)
  }
}

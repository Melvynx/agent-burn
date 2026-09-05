import Charts
import SwiftUI

struct HarnessView: View {
  @Environment(UsageStore.self) private var store
  let agent: String
  var compact = false
  private var color: Color { BurnTheme.color(for: agent) }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 20 : 28) {
      HStack(spacing: 10) {
        HarnessIcon(agent: agent)
        VStack(alignment: .leading, spacing: 3) {
          Text(harnessName(agent)).font(.system(size: 15, weight: .semibold))
          Text(store.reports[agent]?.plan ?? "Subscription usage")
            .font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
        }
        Spacer()
        StatusBadge(
          text: store.errors[agent] != nil
            ? "Needs attention" : store.offline ? "Cached" : "CLI snapshot",
          color: store.errors[agent] != nil ? BurnTheme.accent : color)
      }
      if let error = store.errors[agent] { ReportNotice(message: error) }
      if let report = store.reports[agent] {
        HStack {
          SpendMetric(
            title: "Total spend", value: currency(report.apiEquivalentPerMonth),
            detail: "Past 30 days · API-equivalent")
          if let price = report.pricePerMonth {
            SpendMetric(title: "Monthly plan", value: currency(price), detail: report.plan ?? "")
          }
          if !compact, let economics = report.economics {
            SpendMetric(
              title: "Subscription value",
              value: "\(economics.valueMultiple.formatted(.number.precision(.fractionLength(2))))×",
              detail: "Usage / monthly price")
          }
        }
        if !compact, let economics = report.economics {
          HStack {
            Text("API-equivalent minus plan: \(currency(economics.subsidyPerMonth))")
            Spacer()
            Text(
              "API pricing discount: \(economics.discountPercent.formatted(.number.precision(.fractionLength(1))))%"
            )
          }.font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
        }
      }
      if let forecast = store.forecast(for: agent) {
        if compact {
          quotaHeader(forecast)
          QuotaChart(
            forecast: forecast, samples: store.samples(for: agent), color: color, compact: true)
        } else {
          HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 14) {
              Text("Weekly limit").font(.system(size: 12)).foregroundStyle(BurnTheme.muted)
              quotaHeader(forecast)
              Text("\(currency(forecast.window.apiEquivalentSpent)) used this cycle")
                .font(.system(size: 12)).foregroundStyle(BurnTheme.muted)
            }.frame(width: 280, alignment: .leading)
            QuotaChart(forecast: forecast, samples: store.samples(for: agent), color: color)
          }.padding(.vertical, 10)
        }
        resetDetails(forecast)
        if let short = store.summary?.subscription?.agents.first(where: { $0.agent == agent })?
          .shortWindow
        {
          HStack {
            Text("\(short.label) limit").foregroundStyle(BurnTheme.muted)
            Spacer()
            Text(
              "\(max(0, 100 - short.usedPercent).formatted(.number.precision(.fractionLength(0))))% remaining"
            )
          }.font(.system(size: 12))
        }
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Text(store.isLoading ? "Reading your usage…" : "Quota unavailable")
            .font(.system(size: 24, weight: .semibold))
          Text(
            store.isLoading
              ? "Loading local logs and subscription limits. This can take a moment."
              : "Sign in to this harness and run a session to record limits. Your available spend data appears below."
          )
          .font(.system(size: 13)).foregroundStyle(BurnTheme.muted)
          .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
      }
      if let report = store.reports[agent], !report.topModels.isEmpty {
        Rectangle().fill(BurnTheme.line).frame(height: 1)
        VStack(alignment: .leading, spacing: 14) {
          SectionLabel(title: "Model usage", detail: "API-equivalent · past 30 days")
          ForEach(Array(report.topModels.prefix(compact ? 2 : 6))) { model in
            HStack {
              Text(model.model).lineLimit(1).help(model.model)
              Spacer()
              Text(tokens(model.tokens)).foregroundStyle(BurnTheme.muted)
              Text(currency(model.cost)).frame(width: 80, alignment: .trailing)
            }.font(.system(size: 12)).monospacedDigit()
          }
        }
      }
      if !compact, let report = store.reports[agent] { HarnessSpendDetails(report: report) }
      if let error = store.errors["history"] { ReportNotice(message: error) }
    }
  }

  private func quotaHeader(_ forecast: Forecast) -> some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(forecast.remaining.formatted(.number.precision(.fractionLength(0))))
          .font(.system(size: compact ? 52 : 64, weight: .medium, design: .rounded))
          .monospacedDigit()
        Text("% remaining").font(.system(size: 16)).foregroundStyle(BurnTheme.muted)
        Spacer()
        if compact { Text("Weekly limit").font(.system(size: 11)).foregroundStyle(BurnTheme.muted) }
      }
      VStack(alignment: .leading, spacing: 5) {
        Label(
          forecast.remaining == 0
            ? "Limit reached"
            : forecast.daysEarly > 0.1 ? "A little ahead of pace" : "Room to keep building",
          systemImage: forecast.daysEarly > 0.1
            ? "gauge.with.dots.needle.67percent" : "checkmark.circle"
        )
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(forecast.daysEarly > 0.1 ? BurnTheme.accent : BurnTheme.green)
        Text(
          forecast.projectedUse == nil
            ? "A forecast will appear once this cycle has recorded usage."
            : forecast.daysEarly > 0.1
              ? "At this pace, your quota may run out \(forecast.daysEarly.formatted(.number.precision(.fractionLength(1)))) days early."
              : "Your current pace should carry you through the reset."
        )
        .font(.system(size: 12)).foregroundStyle(BurnTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func resetDetails(_ forecast: Forecast) -> some View {
    VStack(spacing: 12) {
      HStack {
        Label("Resets around", systemImage: "clock").foregroundStyle(BurnTheme.muted)
        Spacer()
        Text(forecast.reset.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
      }
      HStack {
        Label("Suggested pace", systemImage: "speedometer").foregroundStyle(BurnTheme.muted)
        Spacer()
        Text("\(forecast.dailyAllowance.formatted(.number.precision(.fractionLength(1))))% / day")
          .foregroundStyle(color)
      }
      Text("Forecast uses average consumption this cycle; provider limits may change.")
        .font(.system(size: 10)).foregroundStyle(BurnTheme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.system(size: 12)).monospacedDigit()
    .padding(14).background(BurnTheme.surface, in: RoundedRectangle(cornerRadius: 10))
  }
}

import Charts
import SwiftUI

struct NativeUsageView: View {
  @Environment(UsageStore.self) private var store
  let agent: String?
  @State private var modelSearch = ""
  private var own: AgentUsage? { store.summary?.agents.first { $0.agent == agent } }
  private var models: [ModelUsage] {
    agent == nil ? store.summary?.models ?? [] : own?.models ?? []
  }
  private var days: [DailyUsage] { agent == nil ? store.summary?.daily ?? [] : own?.daily ?? [] }
  private var cost: Double {
    agent == nil ? store.summary?.totals.totalCost ?? 0 : own?.totalCost ?? 0
  }
  private var tokenCount: UInt64 {
    agent == nil ? store.summary?.totals.totalTokens ?? 0 : own?.totalTokens ?? 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .center, spacing: 12) {
        if let agent {
          HarnessIcon(agent: agent, size: 40)
        } else {
          Image(systemName: "chart.bar.xaxis").font(.system(size: 26)).foregroundStyle(.tint)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(agent.map(harnessName) ?? "All harnesses").font(.title2.weight(.semibold))
          Text("\(store.period.label) · usage from your logs and connected providers")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer()
        PeriodPicker()
      }
      if let error = store.errors["summary"] { ReportNotice(message: error) }
      if let error = store.errors["cache"] { ReportNotice(message: error) }
      if let error = store.errors["archive"] { ReportNotice(message: error) }
      if store.summary != nil {
        HStack {
          Label(
            "Daily history · \(store.archivedDays(for: agent)) days preserved on this Mac",
            systemImage: "externaldrive.badge.checkmark")
          Spacer()
          Button("Show backup") {
            NSWorkspace.shared.activateFileViewerSelecting([store.archiveURL])
          }
        }.font(.caption).foregroundStyle(.secondary)
        if agent == "cursor" {
          CursorAccountView(
            account: store.summary?.cursorAccount,
            plan: store.summary?.subscription?.agents.first { $0.agent == "cursor" })
        }

        GroupBox {
          HStack(spacing: 24) {
            SpendMetric(title: "Total spend", value: currency(cost), detail: "API-equivalent value")
            Divider()
            SpendMetric(
              title: "Tokens", value: tokens(tokenCount), detail: "Input, output and cache")
            Divider()
            SpendMetric(
              title: "Days recorded", value: days.count.formatted(), detail: store.period.label)
            Divider()
            SpendMetric(
              title: "Models", value: models.count.formatted(),
              detail: agent.map(harnessName) ?? "Across all harnesses")
          }.padding(12).frame(height: 85)
        }
        HStack(alignment: .top, spacing: 18) {
          GroupBox {
            ActivityChart(days: days, color: agent.map(BurnTheme.color) ?? .accentColor)
              .padding(12)
          }.frame(maxWidth: .infinity)
          if agent == nil {
            GroupBox {
              VStack(alignment: .leading, spacing: 16) {
                Text("By harness").font(.headline)
                ScrollView {
                  VStack(spacing: 16) {
                    ForEach(store.summary?.agents ?? []) { usage in
                      Button {
                        store.selection = usage.agent
                      } label: {
                        HStack(spacing: 10) {
                          HarnessIcon(agent: usage.agent, size: 26)
                          VStack(alignment: .leading, spacing: 3) {
                            Text(harnessName(usage.agent)).font(.subheadline.weight(.medium))
                            Text(tokens(usage.totalTokens) + " tokens").font(.caption)
                              .foregroundStyle(
                                .secondary)
                          }
                          Spacer()
                          Text(currency(usage.totalCost)).font(.subheadline).monospacedDigit()
                        }.contentShape(Rectangle())
                      }.buttonStyle(.plain)
                    }
                  }
                }.frame(height: 185)
                Spacer(minLength: 0)
              }.padding(12).frame(height: 218, alignment: .top)
            }.frame(width: 285)
          }
        }
        if let agent, ["codex", "claude"].contains(agent) {
          quotaSection(agent)
        } else if agent != nil && agent != "cursor" {
          Label(
            "This provider does not expose quota limits through Agent Burn.",
            systemImage: "info.circle"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        modelSection
        if agent == "cursor", store.period == .all, let recovered = store.recoveredCursor,
          let models = recovered.models
        {
          GroupBox {
            DisclosureGroup("Recovered model history · \(models.count) models") {
              VStack(alignment: .leading, spacing: 10) {
                Text(
                  "Snapshot: \(recovered.daily?.first?.date ?? "") – \(recovered.daily?.last?.date ?? ""). Current-cycle model data is shown above."
                )
                .font(.caption).foregroundStyle(.secondary)
                ModelUsageTable(models: models, total: recovered.totalCost).frame(height: 280)
              }.padding(.top, 12)
            }.padding(10)
          }
        }
        if let breakdown = own?.tokenBreakdown {
          GroupBox("Token breakdown · available source data") {
            HStack(spacing: 20) {
              SpendMetric(title: "Input", value: tokens(breakdown["input"] ?? 0))
              SpendMetric(title: "Output", value: tokens(breakdown["output"] ?? 0))
              SpendMetric(title: "Cache write", value: tokens(breakdown["cacheWrite"] ?? 0))
              SpendMetric(title: "Cache read", value: tokens(breakdown["cacheRead"] ?? 0))
            }.padding(12)
          }
        }
        if let agent, let report = store.reports[agent] {
          GroupBox {
            DisclosureGroup("Subscription economics, token costs and weekly trends") {
              VStack(alignment: .leading, spacing: 20) {
                HStack {
                  SpendMetric(title: "Past 30 days", value: currency(report.apiEquivalentPerMonth))
                  SpendMetric(
                    title: "Monthly plan",
                    value: report.pricePerMonth.map(currency) ?? "Unavailable")
                  SpendMetric(
                    title: "Subscription value",
                    value: report.economics.map {
                      $0.valueMultiple.formatted(.number.precision(.fractionLength(2))) + "×"
                    } ?? "Unavailable")
                }
                HarnessSpendDetails(report: report)
              }.padding(.top, 18)
            }.font(.headline).padding(10)
          }
        }
        if let subscriptions = store.summary?.subscription?.agents, !subscriptions.isEmpty {
          GroupBox("Subscriptions") {
            HStack(spacing: 30) {
              ForEach(subscriptions.filter { agent == nil || $0.agent == agent }) { subscription in
                LabeledContent(harnessName(subscription.agent)) {
                  Text(
                    (subscription.plan ?? "Unknown plan") + " · "
                      + (subscription.pricePerMonth.map(currency) ?? "Unknown price") + "/mo")
                }
              }
            }.font(.subheadline).padding(10)
          }
        }
        HStack {
          Label(
            "Spend is API-equivalent usage, not your subscription bill.", systemImage: "info.circle"
          )
          Spacer()
          if let first = days.first?.date, let last = days.last?.date { Text("\(first) – \(last)") }
        }.font(.caption).foregroundStyle(.secondary)
      } else {
        ContentUnavailableView {
          Label(
            store.isLoading ? "Loading usage history" : "No report available",
            systemImage: "chart.bar.xaxis")
        } description: {
          Text(
            "Reading your full log folders. Saved reports will appear immediately on future launches."
          )
        }
        .frame(maxWidth: .infinity, minHeight: 380)
      }
    }
  }

  private var modelSection: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Models · available source data").font(.headline)
          Text("\(models.count)").font(.caption).foregroundStyle(.secondary)
          Spacer()
          TextField("Filter models", text: $modelSearch).textFieldStyle(.roundedBorder).frame(
            width: 220)
        }.padding(.horizontal, 6)
        ModelUsageTable(
          models: models.filter {
            modelSearch.isEmpty || $0.model.localizedCaseInsensitiveContains(modelSearch)
          }, total: cost
        )
        .frame(height: CGFloat(min(9, max(3, models.count))) * 27 + 28)
      }.padding(8)
    }
  }

  @ViewBuilder private func quotaSection(_ agent: String) -> some View {
    if let error = store.errors[agent] { ReportNotice(message: error) }
    if let forecast = store.forecast(for: agent) {
      GroupBox {
        HStack(alignment: .top, spacing: 28) {
          VStack(alignment: .leading, spacing: 14) {
            Text("Weekly quota").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
              Text("\(Int(forecast.remaining))%").font(
                .system(size: 42, weight: .semibold, design: .rounded)
              ).monospacedDigit()
              Text("remaining").foregroundStyle(.secondary)
            }
            Label(
              forecast.daysEarly > 0.1 ? "Ahead of pace" : "On track",
              systemImage: forecast.daysEarly > 0.1
                ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
            )
            .foregroundStyle(forecast.daysEarly > 0.1 ? .orange : .green).font(
              .subheadline.weight(.medium))
            Text(
              "Reset: \(forecast.reset.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
            )
            Text(
              "Suggested pace: \(forecast.dailyAllowance.formatted(.number.precision(.fractionLength(1))))% / day"
            )
            Text("Estimate based on this cycle’s average usage.").font(.caption).foregroundStyle(
              .secondary)
          }.font(.subheadline).frame(width: 255, alignment: .leading)
          QuotaChart(
            forecast: forecast, samples: store.samples(for: agent),
            color: BurnTheme.color(for: agent), compact: true)
        }.padding(12)
      }
    } else {
      Label(
        "Quota unavailable. Spend and token history are still shown above.",
        systemImage: "info.circle"
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}

private struct ModelUsageTable: View {
  let models: [ModelUsage]
  let total: Double
  @State private var order = [KeyPathComparator(\ModelUsage.totalCost, order: .reverse)]
  var body: some View {
    Table(models.sorted(using: order), sortOrder: $order) {
      TableColumn("Model", value: \.model) { model in Text(model.model).help(model.model) }
      TableColumn("Tokens", value: \.totalTokens) { model in
        Text(tokens(model.totalTokens)).monospacedDigit().foregroundStyle(.secondary)
      }.width(100)
      TableColumn("Spend", value: \.totalCost) { model in
        Text(currency(model.totalCost)).monospacedDigit()
      }.width(100)
      TableColumn("Share") { model in
        Text(
          total > 0
            ? (model.totalCost / total).formatted(.percent.precision(.fractionLength(1))) : "—"
        )
        .monospacedDigit().foregroundStyle(.secondary)
      }.width(75)
    }.tableStyle(.inset(alternatesRowBackgrounds: true))
  }
}

private struct ActivityChart: View {
  let days: [DailyUsage]
  let color: Color
  @State private var selected: Date?
  private var points: [(date: Date, usage: DailyUsage)] {
    days.compactMap { usage in
      guard let date = try? Date(usage.date + "T00:00:00Z", strategy: .iso8601) else { return nil }
      return (date, usage)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Daily spend").font(.headline)
        Spacer()
        if let selected,
          let point = points.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: selected)
          })
        {
          Text(point.usage.date + " · " + currency(point.usage.cost)).font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("USD").font(.caption).foregroundStyle(.secondary)
        }
      }
      Chart {
        ForEach(points, id: \.usage.id) { point in
          BarMark(x: .value("Day", point.date, unit: .day), y: .value("Spend", point.usage.cost))
            .foregroundStyle(color.gradient).cornerRadius(2)
            .accessibilityLabel(point.usage.date).accessibilityValue(currency(point.usage.cost))
        }
        if let selected {
          RuleMark(x: .value("Day", selected)).foregroundStyle(.secondary.opacity(0.4))
        }
      }
      .chartXSelection(value: $selected)
      .chartYAxis {
        AxisMarks(position: .leading) { _ in
          AxisGridLine()
          AxisValueLabel()
        }
      }
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
          AxisValueLabel(format: .dateTime.month(.abbreviated).day())
        }
      }
      .frame(height: 182)
    }
  }
}

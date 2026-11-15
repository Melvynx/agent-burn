import Charts
import SwiftUI

struct NativeUsageView: View {
  @Environment(UsageStore.self) private var store
  let agent: String?
  @State private var modelSearch = ""
  @State private var cursorScope = CursorModelScope.allModels
  private var own: AgentUsage? { store.summary?.agents.first { $0.agent == agent } }
  private var hasCursorCredits: Bool { cursorHasPromotionalCredits(store.summary?.cursorAccount) }
  private var models: [ModelUsage] {
    let all = agent == nil ? store.summary?.models ?? [] : own?.models ?? []
    return agent == "cursor" && !hasCursorCredits ? modelUsage(all, scope: cursorScope) : all
  }
  private var days: [DailyUsage] {
    let all = agent == nil ? store.summary?.daily ?? [] : own?.daily ?? []
    return agent == "cursor" && !hasCursorCredits ? dailyUsage(all, scope: cursorScope) : all
  }
  private var cost: Double {
    agent == nil ? store.summary?.totals.totalCost ?? 0 : own?.totalCost ?? 0
  }
  private var tokenCount: UInt64 {
    agent == nil ? store.summary?.totals.totalTokens ?? 0 : own?.totalTokens ?? 0
  }
  private var planInAccountHeader: Bool {
    switch agent {
    case "claude", "cursor": true
    case "codex": store.forecast(for: "codex") != nil
    default: false
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if store.summary == nil, let error = store.errors["summary"] {
        ReportNotice(message: error)
      }
      if store.summary != nil {
        meters
        statStrip
        HStack(alignment: .top, spacing: 14) {
          ActivityChart(
            days: days, color: agent.map(BurnTheme.color) ?? BurnTheme.flame,
            domain: store.chartDomain,
            scope: agent == "cursor" && !hasCursorCredits ? $cursorScope : nil,
            series: agent == nil ? store.summary?.agents ?? [] : []
          )
          .frame(maxHeight: .infinity, alignment: .top)
          .burnCard()
          .frame(maxWidth: .infinity)
          if agent == nil { harnessList.frame(width: 280) }
        }
        .fixedSize(horizontal: false, vertical: true)
        if store.hasPeriodDetails { modelSection }
        if agent == "cursor", store.period == .all, let recovered = store.recoveredCursor,
          let models = recovered.models
        {
          DisclosureGroup("Recovered model history · \(models.count) models") {
            VStack(alignment: .leading, spacing: 10) {
              Text(
                "Snapshot: \(recovered.daily?.first?.date ?? "") – \(recovered.daily?.last?.date ?? ""). Current-cycle model data is shown above."
              )
              .font(.caption).foregroundStyle(.secondary)
              ModelUsageTable(models: models, total: recovered.totalCost).frame(height: 280)
            }.padding(.top, 12)
          }
          .font(.system(size: 13, weight: .semibold))
          .burnCard()
        }
        if let breakdown = own?.tokenBreakdown { tokenBreakdown(breakdown) }
        if let agent, let report = store.reports[agent] {
          Group {
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
            }.font(.system(size: 13, weight: .semibold))
          }
          .burnCard()
        }
        if !planInAccountHeader,
          let subscriptions = store.summary?.subscription?.agents.filter({
            agent == nil || $0.agent == agent
          }), !subscriptions.isEmpty
        {
          VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Subscriptions", symbol: "creditcard.fill", tint: .purple) {
              Text("Monthly plan prices")
            }
            HStack(spacing: 10) {
              ForEach(subscriptions) { subscription in
                HStack(spacing: 10) {
                  HarnessIcon(agent: subscription.agent, size: 24)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(harnessName(subscription.agent)).font(.system(size: 12, weight: .medium))
                    Text(subscription.plan ?? "Unknown plan").font(.system(size: 11))
                      .foregroundStyle(.secondary)
                  }
                  Spacer(minLength: 8)
                  Text((subscription.pricePerMonth.map(currency) ?? "—") + "/mo")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(
                  BurnTheme.hover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
              }
            }
          }
          .burnCard()
        }
        HStack {
          Label(
            "Spend is API-equivalent usage, not your subscription bill.", systemImage: "info.circle"
          )
          Spacer()
          if let domain = store.chartDomain {
            Text("\(quotaDayKey(domain.lowerBound)) – \(quotaDayKey(domain.upperBound))")
          }
        }.font(.caption).foregroundStyle(.secondary)
      } else {
        if let agent, ["codex", "claude"].contains(agent) { quotaSection(agent) }
        ContentUnavailableView {
          Label(
            store.isLoading ? "Loading usage history" : "No report available",
            systemImage: "chart.bar.xaxis")
        } description: {
          Text(
            "Your usage will appear here when it is ready."
          )
        }
        .frame(maxWidth: .infinity, minHeight: 380)
      }
    }
  }

  private var statStrip: some View {
    HStack(alignment: .top, spacing: 16) {
      MetricTile(
        title: "Total spend", value: currency(cost), detail: "API-equivalent value",
        symbol: "dollarsign"
      )
      Divider()
      MetricTile(
        title: "Tokens", value: tokens(tokenCount), detail: "Input, output and cache",
        symbol: "square.stack.3d.up.fill", tint: .blue
      )
      Divider()
      MetricTile(
        title: "Avg tokens / $",
        value: quotaTokensPerUnitLabel(
          quotaTokensPerDollar(tokens: tokenCount, cost: cost), unit: "$") ?? "—",
        detail: store.period.label, symbol: "gauge.with.dots.needle.50percent", tint: .green
      )
      Divider()
      MetricTile(
        title: "Models", value: store.hasPeriodDetails ? models.count.formatted() : "—",
        detail: agent.map(harnessName) ?? "Across all harnesses", symbol: "cpu", tint: .purple
      )
    }
    .fixedSize(horizontal: false, vertical: true)
    .burnCard(padding: 16)
  }

  private func tokenBreakdown(_ breakdown: [String: UInt64]) -> some View {
    let parts: [(key: String, label: String, color: Color)] = [
      ("input", "Input", .blue), ("output", "Output", BurnTheme.flame),
      ("cacheWrite", "Cache write", .purple), ("cacheRead", "Cache read", .teal),
    ]
    let total = max(1, parts.reduce(UInt64(0)) { $0 + (breakdown[$1.key] ?? 0) })
    return VStack(alignment: .leading, spacing: 14) {
      CardHeader(title: "Token breakdown", symbol: "square.stack.3d.up.fill", tint: .blue) {
        Text("Available source data")
      }
      GeometryReader { geometry in
        HStack(spacing: 2) {
          ForEach(parts, id: \.key) { part in
            let share = Double(breakdown[part.key] ?? 0) / Double(total)
            if share > 0 {
              Rectangle().fill(part.color.gradient)
                .frame(width: max(2, geometry.size.width * share - 2))
            }
          }
        }
        .clipShape(Capsule())
      }
      .frame(height: 8)
      .accessibilityHidden(true)
      HStack(spacing: 20) {
        ForEach(parts, id: \.key) { part in
          let value = breakdown[part.key] ?? 0
          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
              Circle().fill(part.color).frame(width: 7, height: 7)
              Text(part.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(tokens(value)).font(.system(size: 20, weight: .semibold, design: .rounded))
            Text((Double(value) / Double(total)).formatted(.percent.precision(.fractionLength(1))))
              .font(.system(size: 11)).foregroundStyle(.secondary)
          }
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .combine)
        }
      }
    }
    .burnCard()
  }

  private var harnessList: some View {
    let agents = (store.summary?.agents ?? []).sorted { $0.totalCost > $1.totalCost }
    let top = max(agents.first?.totalCost ?? 0, 0.01)
    return VStack(alignment: .leading, spacing: 10) {
      CardHeader(title: "By harness", symbol: "flame.fill") {
        Text("\(agents.count) active")
      }
      ScrollView {
        VStack(spacing: 2) {
          ForEach(agents) { usage in
            Button {
              store.selection = usage.agent
            } label: {
              HStack(spacing: 10) {
                HarnessIcon(agent: usage.agent, size: 26)
                VStack(alignment: .leading, spacing: 5) {
                  HStack(alignment: .firstTextBaseline) {
                    Text(harnessName(usage.agent)).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(currency(usage.totalCost)).font(.system(size: 12, weight: .semibold))
                  }
                  ShareBar(
                    value: usage.totalCost / top, tint: BurnTheme.color(for: usage.agent),
                    height: 4)
                  Text(tokens(usage.totalTokens) + " tokens").font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                  .foregroundStyle(.tertiary)
              }
              .monospacedDigit()
            }
            .buttonStyle(.plain)
            .hoverRow()
            .help("Open \(harnessName(usage.agent))")
          }
        }
      }
      .scrollIndicators(.never)
      .frame(maxHeight: 214)
      .padding(.horizontal, -8)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .burnCard()
  }

  @ViewBuilder private var meters: some View {
    if agent == "cursor" {
      CursorAccountView(
        account: store.summary?.cursorAccount,
        plan: store.summary?.subscription?.agents.first { $0.agent == "cursor" })
    } else if agent == "claude" {
      ClaudeAccountView(
        account: store.summary?.claudeAccount,
        plan: store.summary?.subscription?.agents.first { $0.agent == "claude" })
    } else if agent == "codex" {
      quotaSection("codex")
      if let days = store.reports["codex"]?.limitUsageDaily,
        days.contains(where: { $0.usedPercent > 0 })
      {
        CodexLimitUsageChart(days: days).burnCard()
      }
    }
  }

  private var modelSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      CardHeader(title: "Models", symbol: "cpu", tint: .purple) {
        HStack(spacing: 10) {
          Text("\(models.count) · available source data")
          HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
            TextField("Filter models", text: $modelSearch).textFieldStyle(.plain)
              .font(.system(size: 12))
          }
          .padding(.horizontal, 9).padding(.vertical, 5)
          .frame(width: 200)
          .background(BurnTheme.track, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
      }
      if models.isEmpty {
        Label("No model usage recorded in this period.", systemImage: "cpu")
          .font(.system(size: 12)).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 60)
      } else {
        ModelUsageTable(
          models: models.filter {
            modelSearch.isEmpty || $0.model.localizedCaseInsensitiveContains(modelSearch)
          },
          total: agent == "cursor" && !hasCursorCredits && cursorScope == .cursorModels
            ? models.reduce(0) { $0 + $1.totalCost } : cost
        )
        .frame(height: CGFloat(min(9, max(3, models.count))) * 24 + 36)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .burnCard()
  }

  @ViewBuilder private func quotaSection(
    _ agent: String, style: QuotaMeterStyle = .weekly
  ) -> some View {
    @Bindable var store = store
    let range = store.chartRange(for: agent)
    if let error = store.errors[agent] { ReportNotice(message: error) }
    if let error = store.errors["quotaService"] { ReportNotice(message: error) }
    if let forecast = store.forecast(for: agent) {
      let plan = store.summary?.subscription?.agents.first { $0.agent == agent }
      VStack(alignment: .leading, spacing: 16) {
        CardHeader(
          title: harnessName(agent) + " " + (plan?.plan ?? "account"),
          symbol: "gauge.with.dots.needle.33percent", tint: BurnTheme.color(for: agent)
        ) {
          HStack(spacing: 12) {
            if let price = plan?.pricePerMonth {
              Text(currency(price) + " / month").monospacedDigit()
            }
            QuotaChartRangePicker(
              range: agent == "cursor" ? $store.cursorQuotaChartRange : $store.quotaChartRange)
          }
        }
        HStack(alignment: .top, spacing: 24) {
          QuotaSummary(
            forecast: forecast,
            samples: store.samples(
              for: agent, range: range, now: store.quotaCheckDate),
            now: store.quotaCheckDate,
            stale: !forecast.isFresh(at: store.quotaCheckDate)
              || store.quotaError(for: agent) != nil,
            staleHelp: store.quotaError(for: agent)
              ?? "Showing the last known reading. Update pending.",
            availableResets: style == .weekly
              ? store.reports[agent]?.resetCreditsAvailable : nil,
            rates: store.blendRates(for: agent),
            style: style
          )
          .frame(width: 236, alignment: .leading)
          QuotaChart(
            forecast: forecast,
            samples: store.samples(
              for: agent, range: range, now: store.quotaCheckDate),
            color: BurnTheme.color(for: agent),
            range: range, now: store.quotaCheckDate,
            resetLabel: style.chartResetLabel
          )
          .id(range)
        }
      }
      .burnCard(padding: 18)
      if style == .promotionalCredits,
        (store.summary?.cursorAccount?.includedPercentUsed ?? 0) == 0
      {
        Text("Included allowance is unused while promotional credits remain.")
          .font(.caption).foregroundStyle(.secondary)
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
        let share = total > 0 ? max(0, min(1, model.totalCost / total)) : 0
        HStack(spacing: 8) {
          Capsule().fill(BurnTheme.track).frame(width: 44, height: 4)
            .overlay(alignment: .leading) {
              Capsule().fill(BurnTheme.flame).frame(width: max(2, 44 * share), height: 4)
            }
            .accessibilityHidden(true)
          Text(total > 0 ? share.formatted(.percent.precision(.fractionLength(1))) : "—")
            .monospacedDigit().foregroundStyle(.secondary)
        }
      }.width(120)
    }.tableStyle(.inset(alternatesRowBackgrounds: true))
  }
}

private struct ActivityChart: View {
  let days: [DailyUsage]
  let color: Color
  var domain: ClosedRange<Date>? = nil
  var scope: Binding<CursorModelScope>? = nil
  var series: [AgentUsage] = []
  @State private var selected: Date?
  @State private var granularityOverride: SpendGranularity?
  private var points: [(date: Date, usage: DailyUsage)] {
    days.compactMap { usage in
      guard let date = usageDayDate(usage.date) else { return nil }
      return (date, usage)
    }
  }
  private var scale: ClosedRange<Date> {
    if let domain { return domain }
    if let first = points.first?.date, let last = points.last?.date, first <= last {
      return first...last
    }
    let today = Calendar(identifier: .gregorian).startOfDay(for: .now)
    return today...today
  }
  private var spanDays: Int { spendSpanDays(lower: scale.lowerBound, upper: scale.upperBound) }
  private var effective: SpendGranularity {
    granularityOverride ?? spendGranularityAuto(spanDays: spanDays)
  }
  private var granularityBinding: Binding<SpendGranularity> {
    Binding(get: { effective }, set: { granularityOverride = $0 })
  }
  private var buckets: [(date: Date, end: Date, usage: DailyUsage)] {
    let calendar = spendCalendar()
    return bucketDailyUsage(days, granularity: effective, calendar: calendar).compactMap { usage in
      guard let start = usageDayDate(usage.date) else { return nil }
      return (
        start, spendBucketEnd(start: start, granularity: effective, calendar: calendar), usage
      )
    }
  }
  private var selectedBucket: (date: Date, end: Date, usage: DailyUsage)? {
    guard let selected else { return nil }
    return buckets.first { selected >= $0.date && selected <= $0.end }
  }
  // Largest harness first so it sits at the bottom of every stacked bar.
  private var stacked: [SpendSegment] {
    let calendar = spendCalendar()
    return series.sorted { $0.totalCost > $1.totalCost }.flatMap { agent in
      bucketDailyUsage(agent.daily ?? [], granularity: effective, calendar: calendar)
        .compactMap { usage -> SpendSegment? in
          guard usage.cost > 0, let date = usageDayDate(usage.date) else { return nil }
          return SpendSegment(date: date, agent: agent.agent, cost: usage.cost)
        }
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        IconBadge(symbol: "chart.bar.fill", tint: color)
        Text(effective.spendTitle).font(.system(size: 13, weight: .semibold))
        Picker("Granularity", selection: granularityBinding) {
          ForEach(SpendGranularity.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
        .labelsHidden()
        .accessibilityLabel("Spend granularity")
        if let scope {
          Picker("Models", selection: scope) {
            ForEach(CursorModelScope.allCases) { option in
              Text(option.label).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 260)
          .labelsHidden()
          .accessibilityLabel("Daily spend models")
        }
        Spacer()
        if let bucket = selectedBucket {
          Text(
            spendBucketTooltip(start: bucket.date, granularity: effective, cost: bucket.usage.cost)
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } else {
          Text("USD").font(.caption).foregroundStyle(.secondary)
        }
      }
      Chart {
        if stacked.isEmpty {
          ForEach(buckets, id: \.usage.id) { bucket in
            BarMark(
              x: .value("Day", bucket.date, unit: effective.unit),
              y: .value("Spend", bucket.usage.cost)
            )
            .foregroundStyle(color.gradient).cornerRadius(3)
            .opacity(
              selectedBucket == nil || selectedBucket?.usage.id == bucket.usage.id ? 1 : 0.35
            )
            .accessibilityLabel(bucket.usage.date).accessibilityValue(currency(bucket.usage.cost))
          }
        } else {
          ForEach(stacked) { segment in
            BarMark(
              x: .value("Day", segment.date, unit: effective.unit),
              y: .value("Spend", segment.cost)
            )
            .foregroundStyle(BurnTheme.color(for: segment.agent).gradient)
            .opacity(selectedBucket == nil || selectedBucket?.date == segment.date ? 1 : 0.35)
            .accessibilityLabel("\(harnessName(segment.agent)) \(quotaDayKey(segment.date))")
            .accessibilityValue(currency(segment.cost))
          }
        }
        if let bucket = selectedBucket {
          RuleMark(x: .value("Day", bucket.date, unit: effective.unit))
            .foregroundStyle(color.opacity(0.25))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(
              position: .top, spacing: 4,
              overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
            ) {
              let parts = stacked.filter { $0.date == bucket.date }.sorted { $0.cost > $1.cost }
              if parts.isEmpty {
                Text(currency(bucket.usage.cost))
                  .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                  .padding(.horizontal, 8).padding(.vertical, 4)
                  .background(.regularMaterial, in: Capsule())
                  .overlay(Capsule().strokeBorder(BurnTheme.cardStroke, lineWidth: 1))
              } else {
                VStack(alignment: .leading, spacing: 4) {
                  Text(currency(bucket.usage.cost)).font(.system(size: 12, weight: .semibold))
                  ForEach(parts.prefix(4)) { part in
                    HStack(spacing: 6) {
                      Circle().fill(BurnTheme.color(for: part.agent)).frame(width: 6, height: 6)
                      Text(harnessName(part.agent)).foregroundStyle(.secondary)
                      Spacer(minLength: 10)
                      Text(currency(part.cost))
                    }
                    .font(.system(size: 10))
                  }
                }
                .monospacedDigit()
                .frame(width: 170)
                .padding(9)
                .background(
                  .regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(BurnTheme.cardStroke, lineWidth: 1))
              }
            }
        }
      }
      .animation(.easeOut(duration: 0.15), value: selectedBucket?.usage.id)
      .chartXSelection(value: $selected)
      .chartXScale(domain: spendChartDomain(scale, granularity: effective))
      .chartYAxis {
        AxisMarks(position: .leading) { _ in
          AxisGridLine()
          AxisValueLabel()
        }
      }
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
          if effective == .monthly {
            AxisValueLabel(format: .dateTime.month(.abbreviated).year())
          } else {
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
          }
        }
      }
      .frame(height: 182)
      .overlay {
        if buckets.allSatisfy({ $0.usage.cost <= 0 }) {
          VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 22))
              .foregroundStyle(.tertiary)
            Text("No spend in this period").font(.system(size: 13, weight: .medium))
            Text("Choose a longer range or run a session with this agent.")
              .font(.system(size: 11)).foregroundStyle(.secondary)
          }
          .padding(.horizontal, 16).padding(.vertical, 12)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
      }
      .id(effective.rawValue + scale.lowerBound.formatted() + scale.upperBound.formatted())
      if !stacked.isEmpty { legend }
    }
  }

  private var legend: some View {
    let agents = series.filter { $0.totalCost > 0 && !($0.daily ?? []).isEmpty }
      .sorted { $0.totalCost > $1.totalCost }
    return HStack(spacing: 14) {
      ForEach(agents.prefix(5)) { agent in
        HStack(spacing: 5) {
          Circle().fill(BurnTheme.color(for: agent.agent)).frame(width: 7, height: 7)
          Text(harnessName(agent.agent))
        }
        .fixedSize()
      }
      if agents.count > 5 {
        Text("+\(agents.count - 5)").fixedSize()
          .help(agents.dropFirst(5).map { harnessName($0.agent) }.joined(separator: ", "))
      }
      Spacer(minLength: 0)
    }
    .font(.system(size: 11)).foregroundStyle(.secondary)
    .accessibilityElement(children: .combine)
  }
}

private struct SpendSegment: Identifiable {
  let date: Date
  let agent: String
  let cost: Double
  var id: String { agent + "|" + date.timeIntervalSince1970.description }
}

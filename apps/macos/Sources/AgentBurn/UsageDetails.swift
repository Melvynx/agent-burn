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

struct QuotaSummary: View {
  let forecast: Forecast
  let samples: [QuotaSample]
  let now: Date
  var stale = false
  var staleHelp: String?
  var compact = false
  var availableResets: Int? = nil
  var rates: QuotaBlendRates? = nil
  var style = QuotaMeterStyle.weekly
  private var muted: Color { compact ? BurnTheme.quotaMuted : BurnTheme.muted }
  private var reading: QuotaChartReading {
    quotaChartReading(at: forecast.observedAt, samples: samples, forecast: forecast, range: .rte)
  }
  private var paceText: String? { quotaChartDeltaText(reading.paceDelta) }
  private var paceColor: Color {
    reading.paceDelta.map { $0 < -0.05 ? BurnTheme.behind : BurnTheme.ahead } ?? muted
  }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 14 : 20) {
      if !compact { title }
      if compact { compactHero } else { hero }
      if !compact { facts }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var title: some View {
    HStack(spacing: 6) {
      Text(style.title).font(.headline).lineLimit(1)
      if stale { staleMark }
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 10) {
      remainingLabel
      if let paceText {
        StatusBadge(text: paceText, color: paceColor)
          .help("Recorded remaining minus even pace at the latest reading.")
      }
      remainingBar
    }
  }

  private var compactHero: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        remainingLabel
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 6) {
          if let paceText {
            StatusBadge(text: paceText, color: paceColor)
              .help("Recorded remaining minus even pace at the latest reading.")
          }
          Text("\(style.resetTitle) \(quotaTimeLeft(forecast, now: now))")
            .font(.system(size: 12))
            .foregroundStyle(muted)
            .lineLimit(1)
          Text(quotaDateCompact(forecast.reset))
            .font(.system(size: 12))
            .foregroundStyle(muted)
            .monospacedDigit()
            .lineLimit(1)
            .help(style.resetHelp)
          if let availableResets {
            Text(availableResets == 1 ? "1 reset" : "\(availableResets) resets")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(BurnTheme.ink)
              .lineLimit(1)
              .help("Codex rate-limit resets you can redeem now.")
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(style.resetTitle)
        .accessibilityValue(
          "\(quotaTimeLeft(forecast, now: now)). \(quotaDateCompact(forecast.reset))")
      }
      remainingBar
    }
  }

  private var remainingLabel: some View {
    VStack(alignment: .leading, spacing: 2) {
      if compact {
        HStack(spacing: 6) {
          Text(style.remainingCaption).font(.system(size: 12)).foregroundStyle(muted).lineLimit(1)
          if stale { staleMark }
        }
      }
      Text(quotaChartPercentLabel(forecast.remaining))
        .font(.system(size: compact ? 44 : 42, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(BurnTheme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      if !compact {
        Text("remaining").font(.system(size: 13)).foregroundStyle(muted)
      }
    }
    .help(
      "Updated \(forecast.observedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second()))"
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Remaining quota")
    .accessibilityValue(quotaChartPercentLabel(forecast.remaining))
  }

  @ViewBuilder private var staleMark: some View {
    Image(systemName: "clock.badge.exclamationmark")
      .foregroundStyle(.orange)
      .help(staleHelp ?? "Showing the last known reading. Update pending.")
      .accessibilityLabel("Last known quota; update pending")
  }

  private var facts: some View {
    VStack(spacing: 11) {
      row(
        style.resetTitle, quotaTimeLeft(forecast, now: now),
        detail: quotaDateCompact(forecast.reset),
        help: style.resetHelp)
      row(
        "Used",
        "\(quotaUsedPercent(forecast).formatted(.number.precision(.fractionLength(1))))%",
        detail: "since \(quotaDayLabel(forecast.start))",
        help: style.usedHelp
      )
      row(
        "Daily",
        "\(forecast.dailyAllowance.formatted(.number.precision(.fractionLength(1))))%\u{00A0}/ day",
        help: "Remaining quota divided by the time until reset.")
      if let dollars = quotaDollarsPerPercentLabel(rates?.dollarsPerPercent) {
        row(
          "Avg $ / %", dollars,
          detail: quotaTokensPerUnitLabel(rates?.tokensPerDollar, unit: "$"),
          help:
            "API-equivalent spend this cycle divided by used quota percent. Tokens / $ uses logged tokens for the same days, or the last 30 days of model usage when cycle tokens are missing."
        )
      } else if let tokensPer = quotaTokensPerUnitLabel(rates?.tokensPerDollar, unit: "$") {
        row(
          "Avg tokens / $", tokensPer,
          help: "Logged tokens divided by API-equivalent spend.")
      }
      if let available = availableResets {
        row(
          "Resets", "\(available)",
          detail: "banked",
          help: "Codex rate-limit resets you can redeem now.")
      }
    }
  }

  private var remainingBar: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(BurnTheme.elevated)
        Capsule().fill(paceColor.opacity(0.85)).frame(
          width: geo.size.width * max(0, min(1, forecast.remaining / 100)))
      }
    }
    .frame(height: 5)
    .accessibilityHidden(true)
  }

  private func row(_ title: String, _ value: String, detail: String? = nil, help: String)
    -> some View
  {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title).foregroundStyle(muted).lineLimit(1)
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 1) {
        Text(value)
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
        if let detail {
          Text(detail)
            .foregroundStyle(muted)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .allowsTightening(true)
        }
      }
      .multilineTextAlignment(.trailing)
      .layoutPriority(1)
    }
    .font(.system(size: 12))
    .help(help)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue(detail.map { "\(value). \($0)" } ?? value)
  }
}

struct DailySpendChart: View {
  let title: String
  let days: [DailyUsage]
  var color = BurnTheme.accent
  var scope: Binding<CursorModelScope>? = nil
  var domain: ClosedRange<Date>? = nil
  var showsGranularity = true
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
    guard showsGranularity else { return .daily }
    return granularityOverride ?? spendGranularityAuto(spanDays: spanDays)
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
  private var headerTitle: String { showsGranularity ? effective.spendTitle : title }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        SectionLabel(title: headerTitle, detail: "API-equivalent USD")
        Spacer()
        if showsGranularity {
          Picker("Granularity", selection: granularityBinding) {
            ForEach(SpendGranularity.allCases) { option in
              Text(option.label).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .frame(width: 220)
          .labelsHidden()
          .accessibilityLabel("Spend granularity")
        }
        if let scope {
          Picker("Models", selection: scope) {
            ForEach(CursorModelScope.allCases) { option in
              Text(option.label).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 240)
          .labelsHidden()
          .accessibilityLabel("Daily spend models")
        }
      }
      Chart {
        ForEach(buckets, id: \.usage.id) { bucket in
          BarMark(
            x: .value("Day", bucket.date, unit: effective.unit),
            y: .value("Usage", bucket.usage.cost)
          )
          .foregroundStyle(color).cornerRadius(3)
          .accessibilityLabel(bucket.usage.date).accessibilityValue(currency(bucket.usage.cost))
        }
        if let selected {
          RuleMark(x: .value("Day", selected)).foregroundStyle(.secondary.opacity(0.4))
        }
      }
      .chartXSelection(value: $selected)
      .chartXScale(domain: scale)
      .chartYAxis {
        AxisMarks(position: .leading) { _ in
          AxisGridLine().foregroundStyle(BurnTheme.line)
          AxisValueLabel().foregroundStyle(BurnTheme.muted)
        }
      }
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
          if effective == .monthly {
            AxisValueLabel(format: .dateTime.month(.abbreviated).year()).foregroundStyle(
              BurnTheme.muted)
          } else {
            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(
              BurnTheme.muted)
          }
        }
      }
      .frame(height: 150)
      .id(
        "\(showsGranularity)-\(effective.rawValue)-\(scale.lowerBound.formatted())-\(scale.upperBound.formatted())"
      )
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
          color: BurnTheme.color(for: report.agent), showsGranularity: false)
      }
      if let estimate = report.estimate {
        VStack(alignment: .leading, spacing: 14) {
          SectionLabel(title: "Quota value estimate", detail: "Based on current cycle")
          detail("Full quota value", currency(estimate.fullQuotaValue))
          if let dollars = quotaDollarsPerPercentLabel(estimate.fullQuotaValue / 100) {
            detail("Average $ / %", dollars)
          }
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
  @State private var cursorScope = CursorModelScope.allModels
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
        if agent == "cursor", cursorHasPromotionalCredits(store.summary?.cursorAccount),
          let forecast = store.forecast(for: "cursor")
        {
          QuotaSummary(
            forecast: forecast,
            samples: store.samples(
              for: "cursor", range: store.cursorQuotaChartRange, now: store.quotaCheckDate),
            now: store.quotaCheckDate,
            stale: !forecast.isFresh(at: store.quotaCheckDate)
              || store.quotaError(for: "cursor") != nil,
            staleHelp: store.quotaError(for: "cursor")
              ?? "Showing the last known reading. Update pending.",
            compact: compact,
            rates: store.blendRates(for: "cursor"),
            style: .promotionalCredits)
          QuotaChart(
            forecast: forecast,
            samples: store.samples(
              for: "cursor", range: store.cursorQuotaChartRange, now: store.quotaCheckDate),
            color: compact
              ? BurnTheme.quotaColor(for: "cursor") : BurnTheme.color(for: "cursor"),
            compact: compact, range: store.cursorQuotaChartRange, now: store.quotaCheckDate,
            resetLabel: QuotaMeterStyle.promotionalCredits.chartResetLabel)
        } else if agent == "cursor" {
          CursorAccountView(account: store.summary?.cursorAccount, plan: subscription)
        } else if agent == "claude" {
          ClaudeAccountView(account: store.summary?.claudeAccount, plan: subscription)
        }
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
        if let daily = usage.daily, !daily.isEmpty,
          !(compact && cursorHasPromotionalCredits(store.summary?.cursorAccount))
        {
          DailySpendChart(
            title: "Daily usage",
            days: agent == "cursor" && !cursorHasPromotionalCredits(store.summary?.cursorAccount)
              ? dailyUsage(daily, scope: cursorScope) : daily,
            color: BurnTheme.color(for: agent),
            scope: agent == "cursor" && !cursorHasPromotionalCredits(store.summary?.cursorAccount)
              ? $cursorScope : nil,
            domain: store.chartDomain)
        }
        if let models = usage.models, !models.isEmpty {
          let shown =
            agent == "cursor" && !cursorHasPromotionalCredits(store.summary?.cursorAccount)
            ? modelUsage(models, scope: cursorScope) : models
          VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Model breakdown", detail: store.period.label)
            ForEach(Array(shown.prefix(compact ? 3 : shown.count))) { model in
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
    }.labelsHidden().frame(width: 160)
  }
}

struct QuotaChartRangePicker: View {
  @Binding var range: QuotaChartRange
  var body: some View {
    Picker("Quota chart range", selection: $range) {
      ForEach(QuotaChartRange.allCases) { range in Text(range.label).tag(range) }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .frame(width: 160)
    .help("Changes only the weekly quota chart. Spend period stays independent.")
    .accessibilityLabel("Quota chart range")
  }
}

import Charts
import SwiftUI

func quotaChartRecordedStroke(ahead: Bool, color: Color) -> Color {
  ahead ? color : BurnTheme.behind
}

struct QuotaChart: View {
  let forecast: Forecast
  let samples: [QuotaSample]
  let color: Color
  var compact = false
  var range = QuotaChartRange.rte
  var now = Date.now
  var resetLabel = "Reset"
  @State private var selected: Date?
  private var muted: Color { compact ? BurnTheme.quotaMuted : BurnTheme.muted }
  private var domain: ClosedRange<Date> {
    quotaChartWindow(range: range, forecast: forecast, now: now)
  }
  private var scale: ClosedRange<Date> {
    quotaChartScale(range: range, forecast: forecast, now: now)
  }
  private var gridDates: [Date] { quotaChartGridDates(range: range, forecast: forecast, now: now) }
  private var showsForecast: Bool { range == .rte && forecast.projectedUse != nil }
  private var showsIdeal: Bool { range == .rte || range == .rtd }
  private var showsLatest: Bool { domain.contains(forecast.observedAt) }
  private var cursor: Date { selected ?? forecast.observedAt }
  private var drawnSamples: [QuotaSample] { quotaChartSmoothedSamples(samples) }
  private var reading: QuotaChartReading {
    quotaChartReading(at: cursor, samples: drawnSamples, forecast: forecast, range: range)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 8 : 10) {
      header
      chart
    }
    .id(range.rawValue + domain.lowerBound.formatted() + domain.upperBound.formatted())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Quota forecast")
    .accessibilityValue(accessibilityValue)
    .accessibilityHint("Adjust to move the cursor one day at a time.")
    .accessibilityAdjustableAction { direction in
      selected = quotaChartStep(
        from: cursor, forward: direction == .increment, marks: gridDates, domain: domain)
    }
    .help(
      "Drag across the chart to read remaining quota at any time. Recorded stays connected through missing collector readings. Pace spreads the weekly limit evenly until reset. Forecast projects observed usage until the next reset. The recorded line and fill stay green while remaining is ahead of pace, and turn red where remaining falls behind."
    )
  }

  private var chart: some View {
    Chart {
      dayBands
      RuleMark(x: .value("Date", domain.lowerBound)).foregroundStyle(.clear)
      RuleMark(x: .value("Date", domain.upperBound)).foregroundStyle(.clear)
      if showsIdeal { paceBand } else { recordedArea }
      if showsIdeal { idealLine }
      recordedLine
      if showsForecast { forecastLine }
      if showsIdeal && range == .rte && domain.contains(forecast.reset) { resetRule }
      cursorMarks
    }
    .chartXScale(domain: scale.lowerBound...scale.upperBound)
    .chartYScale(domain: 0...100)
    .chartXSelection(value: $selected)
    .chartYAxis {
      AxisMarks(position: .leading, values: compact ? [0, 50, 100] : [0, 25, 50, 75, 100]) {
        value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5])).foregroundStyle(
          BurnTheme.line)
        AxisValueLabel {
          if let number = value.as(Int.self) {
            Text("\(number)%").foregroundStyle(muted).monospacedDigit()
          }
        }
      }
    }
    .chartXAxis {
      let axisDates = quotaChartAxisDates(range: range, forecast: forecast, now: now)
      AxisMarks(values: gridDates) { _ in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(BurnTheme.grid)
      }
      AxisMarks(values: axisDates) { value in
        AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(BurnTheme.grid)
        // The last midday label hugs its tick so the trailing edge never truncates it.
        AxisValueLabel(anchor: value.index == value.count - 1 ? .topTrailing : nil) {
          if let date = value.as(Date.self) {
            Text(quotaChartAxisLabel(date, range: range, marks: axisDates, compact: compact))
              .foregroundStyle(muted)
              .monospacedDigit()
          }
        }
      }
    }
    .frame(height: compact ? 176 : 250)
  }

  @ChartContentBuilder private var dayBands: some ChartContent {
    ForEach(
      Array(quotaChartDayBands(range: range, forecast: forecast, now: now).enumerated()),
      id: \.offset
    ) { _, band in
      if band.isCurrent {
        RectangleMark(
          xStart: .value("Start", band.start), xEnd: .value("End", band.end),
          yStart: .value("Low", 0), yEnd: .value("High", 100)
        )
        .foregroundStyle(color.opacity(0.07))
      }
    }
  }

  @ChartContentBuilder private var paceBand: some ChartContent {
    ForEach(
      Array(quotaChartDeltaSegments(samples: drawnSamples, forecast: forecast).enumerated()),
      id: \.offset
    ) { index, segment in
      ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
        AreaMark(
          x: .value("Date", point.date),
          yStart: .value("Pace", point.ideal),
          yEnd: .value("Recorded", point.recorded),
          series: .value("Series", "Pace delta \(index)")
        )
        .foregroundStyle((segment.ahead ? BurnTheme.ahead : BurnTheme.behind).opacity(0.28))
        .interpolationMethod(.monotone)
      }
    }
  }

  @ChartContentBuilder private var recordedArea: some ChartContent {
    ForEach(Array(drawnSamples.enumerated()), id: \.offset) { _, sample in
      AreaMark(
        x: .value("Date", sample.date), y: .value("Remaining", sample.remaining),
        series: .value("Series", "Recorded area")
      )
      .foregroundStyle(color.opacity(0.12))
      .interpolationMethod(.monotone)
    }
  }

  @ChartContentBuilder private var idealLine: some ChartContent {
    ForEach([domain.lowerBound, min(domain.upperBound, forecast.reset)], id: \.self) { date in
      LineMark(
        x: .value("Date", date),
        y: .value("Remaining", quotaChartIdealRemaining(at: date, forecast: forecast)),
        series: .value("Series", "Pace")
      )
      .foregroundStyle(muted)
      .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
    }
  }

  @ChartContentBuilder private var recordedLine: some ChartContent {
    if showsIdeal {
      ForEach(
        Array(quotaChartDeltaSegments(samples: drawnSamples, forecast: forecast).enumerated()),
        id: \.offset
      ) { index, segment in
        ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
          LineMark(
            x: .value("Date", point.date),
            y: .value("Remaining", point.recorded),
            series: .value("Series", "Recorded \(index)")
          )
          .foregroundStyle(quotaChartRecordedStroke(ahead: segment.ahead, color: color))
          .lineStyle(StrokeStyle(lineWidth: 2.5))
          .interpolationMethod(.monotone)
        }
      }
    } else {
      ForEach(
        Array(
          quotaRecordedSegments(drawnSamples, connectGaps: range.connectsRecordedGaps).enumerated()
        ),
        id: \.offset
      ) { index, segment in
        ForEach(Array(segment.enumerated()), id: \.offset) { _, sample in
          LineMark(
            x: .value("Date", sample.date), y: .value("Remaining", sample.remaining),
            series: .value("Series", "Recorded \(index)")
          )
          .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.5))
          .interpolationMethod(.monotone)
          if segment.count == 1 {
            PointMark(x: .value("Date", sample.date), y: .value("Remaining", sample.remaining))
              .foregroundStyle(color).symbolSize(18)
          }
        }
      }
    }
  }

  @ChartContentBuilder private var forecastLine: some ChartContent {
    ForEach([0, 1], id: \.self) { index in
      LineMark(
        x: .value("Date", index == 0 ? forecast.observedAt : forecast.projectedEnd),
        y: .value("Remaining", index == 0 ? forecast.remaining : forecast.projectedRemaining),
        series: .value("Series", "Forecast")
      )
      .foregroundStyle(forecastStroke.opacity(0.8))
      .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 5]))
    }
  }

  @ChartContentBuilder private var resetRule: some ChartContent {
    RuleMark(x: .value("Date", forecast.reset))
      .foregroundStyle(muted.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
      .annotation(position: .leading, alignment: .top, spacing: 4) {
        Text(resetLabel).font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
      }
  }

  @ChartContentBuilder private var cursorMarks: some ChartContent {
    if domain.contains(cursor) {
      RuleMark(x: .value("Date", cursor))
        .foregroundStyle(color.opacity(selected == nil ? 0.35 : 0.5))
        .lineStyle(StrokeStyle(lineWidth: 1))
      if let value = reading.value {
        PointMark(x: .value("Date", cursor), y: .value("Remaining", value))
          .foregroundStyle(reading.projected ? cursorStroke.opacity(0.6) : cursorStroke)
          .symbolSize(reading.projected ? 30 : 48)
          .annotation(
            position: .top, spacing: compact ? 4 : 8,
            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
          ) {
            deltaBadge
          }
      }
    }
  }

  private var deltaBadge: some View {
    let delta = reading.paceDelta
    let tone: Color = delta.map { $0 < -0.05 ? BurnTheme.behind : BurnTheme.ahead } ?? muted
    return HStack(spacing: compact ? 3 : 6) {
      Text(quotaChartPercentLabel(reading.value))
        .foregroundStyle(BurnTheme.ink.opacity(compact ? 0.88 : 0.94))
      if let text = badgeDelta(delta) {
        Text("·").foregroundStyle(muted.opacity(0.55))
        Text(text).foregroundStyle(tone.opacity(0.88))
      }
    }
    .font(.system(size: compact ? 9.5 : 11, weight: .medium)).monospacedDigit()
    .padding(.horizontal, compact ? 6 : 8).padding(.vertical, compact ? 2.5 : 4)
    .background {
      Capsule()
        .fill(.ultraThinMaterial)
        .opacity(compact ? 0.58 : 0.86)
    }
    .overlay(Capsule().stroke(Color.white.opacity(compact ? 0.10 : 0.16), lineWidth: 0.5))
  }

  private func badgeDelta(_ delta: Double?) -> String? {
    guard let delta else { return nil }
    if compact {
      if abs(delta) < 0.05 { return "pace" }
      let magnitude = abs(delta).formatted(.number.precision(.fractionLength(1)))
      return delta > 0 ? "+\(magnitude)%" : "−\(magnitude)%"
    }
    return quotaChartDeltaText(delta)
  }

  private var header: some View {
    Group {
      if compact {
        cursorLabel
      } else {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
          headerSeries
          Spacer(minLength: 8)
          cursorLabel
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var cursorLabel: some View {
    Text(
      (reading.projected ? "Projected · " : selected == nil ? "Latest · " : "")
        + quotaChartCursorLabel(cursor, range: range)
    )
    .font(.system(size: 12)).foregroundStyle(muted).monospacedDigit()
  }

  private var cursorStroke: Color {
    quotaChartRecordedStroke(ahead: (reading.paceDelta ?? 0) >= 0, color: color)
  }

  private var forecastStroke: Color {
    quotaChartRecordedStroke(
      ahead: forecast.remaining
        >= quotaChartIdealRemaining(
          at: forecast.observedAt, forecast: forecast),
      color: color)
  }

  private var headerSeries: some View {
    HStack(alignment: .firstTextBaseline, spacing: compact ? 12 : 16) {
      series("Recorded", reading.recorded, color: cursorStroke, dashed: false)
      if showsForecast { series("Forecast", reading.forecast, color: forecastStroke, dashed: true) }
      if showsIdeal { series("Pace", reading.ideal, color: muted, dashed: true) }
    }
  }

  private var accessibilityValue: String {
    var parts = [
      "\(quotaChartPercentLabel(reading.value)) remaining at \(quotaChartCursorLabel(cursor, range: range))"
    ]
    if let delta = quotaChartDeltaText(reading.paceDelta) { parts.append(delta + " pace") }
    if reading.projected { parts.append("Projected") }
    parts.append(range.label)
    return parts.joined(separator: ". ") + "."
  }

  private func series(_ title: String, _ value: Double?, color: Color, dashed: Bool) -> some View {
    HStack(spacing: 6) {
      Path { path in
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 14, y: 0))
      }
      .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 3] : []))
      .frame(width: 14, height: 1)
      Text(title).foregroundStyle(muted)
      Text(quotaChartPercentLabel(value)).foregroundStyle(BurnTheme.ink).monospacedDigit()
    }
    .font(.system(size: 12))
  }
}

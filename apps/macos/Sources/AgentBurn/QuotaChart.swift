import Charts
import SwiftUI

struct QuotaChart: View {
  let forecast: Forecast
  let samples: [QuotaSample]
  let color: Color
  var compact = false
  var range = QuotaChartRange.rte
  var now = Date.now
  private var muted: Color { compact ? BurnTheme.quotaMuted : BurnTheme.muted }
  private var domain: ClosedRange<Date> {
    quotaChartWindow(range: range, forecast: forecast, now: now)
  }
  private var showsForecast: Bool { range == .rte && forecast.projectedUse != nil }
  private var showsIdeal: Bool { range == .rte || range == .rtd }
  private var showsLatest: Bool { domain.contains(forecast.observedAt) }
  private var xStride: Int {
    domain.upperBound.timeIntervalSince(domain.lowerBound) > 10 * 86_400 ? 4 : (compact ? 2 : 1)
  }
  private func remainingOnIdeal(at date: Date) -> Double {
    max(0, min(100, 100 * (1 - date.timeIntervalSince(forecast.start) / forecast.duration)))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 10 : 16) {
      HStack(spacing: 16) {
        legend("Recorded", color: color, dashed: false)
        if showsForecast { legend("Forecast", color: color, dashed: true) }
        if showsIdeal { legend("Ideal pace", color: muted, dashed: true) }
      }
      Chart {
        RuleMark(x: .value("Date", domain.lowerBound)).foregroundStyle(.clear)
        RuleMark(x: .value("Date", domain.upperBound)).foregroundStyle(.clear)
        if showsIdeal {
          ForEach([0, 1], id: \.self) { index in
            LineMark(
              x: .value(
                "Date", index == 0 ? domain.lowerBound : min(domain.upperBound, forecast.reset)),
              y: .value(
                "Remaining",
                remainingOnIdeal(
                  at: index == 0 ? domain.lowerBound : min(domain.upperBound, forecast.reset))),
              series: .value("Series", "Ideal pace")
            )
            .foregroundStyle(muted)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
          }
        }
        ForEach(
          Array(
            quotaRecordedSegments(samples, connectGaps: range.connectsRecordedGaps).enumerated()),
          id: \.offset
        ) { index, segment in
          ForEach(Array(segment.enumerated()), id: \.offset) { _, sample in
            LineMark(
              x: .value("Date", sample.date), y: .value("Remaining", sample.remaining),
              series: .value("Series", "Recorded \(index)")
            )
            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(range.connectsRecordedGaps ? .linear : .stepEnd)
            if segment.count == 1 {
              PointMark(x: .value("Date", sample.date), y: .value("Remaining", sample.remaining))
                .foregroundStyle(color).symbolSize(18)
            }
          }
        }
        if showsForecast {
          ForEach([0, 1], id: \.self) { index in
            LineMark(
              x: .value("Date", index == 0 ? forecast.observedAt : forecast.projectedEnd),
              y: .value("Remaining", index == 0 ? forecast.remaining : forecast.projectedRemaining),
              series: .value("Series", "Forecast")
            )
            .foregroundStyle(color.opacity(compact ? 1 : 0.8))
            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 5]))
          }
        }
        if showsLatest {
          RuleMark(x: .value("Date", forecast.observedAt))
            .foregroundStyle(BurnTheme.line).lineStyle(StrokeStyle(lineWidth: 1))
          PointMark(
            x: .value("Date", forecast.observedAt), y: .value("Remaining", forecast.remaining)
          )
          .foregroundStyle(color).symbolSize(55)
          .annotation(position: .top, spacing: 9) {
            if !compact {
              Text("Latest").font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(BurnTheme.elevated, in: Capsule())
            }
          }
        }
      }
      .chartXScale(domain: domain.lowerBound...domain.upperBound)
      .chartPlotStyle { $0.padding(.horizontal, compact ? 10 : 14) }
      .chartYScale(domain: 0...105)
      .id(range.rawValue + domain.lowerBound.formatted() + domain.upperBound.formatted())
      .chartYAxis {
        AxisMarks(position: .leading, values: compact ? [0, 50, 100] : [0, 25, 50, 75, 100]) {
          value in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5])).foregroundStyle(
            BurnTheme.line)
          AxisValueLabel {
            if let number = value.as(Int.self) {
              Text("\(number)%").foregroundStyle(muted)
            }
          }
        }
      }
      .chartXAxis {
        let axisDates = quotaChartAxisDates(range: range, forecast: forecast, now: now)
        if axisDates.isEmpty {
          AxisMarks(
            values: range == .today
              ? .stride(by: .hour, count: 3) : .stride(by: .day, count: xStride)
          ) { _ in
            AxisValueLabel(
              format: range == .today ? .dateTime.hour() : .dateTime.month(.abbreviated).day()
            ).foregroundStyle(muted)
          }
        } else {
          AxisMarks(values: axisDates) { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(muted)
          }
        }
      }
      .frame(height: compact ? 150 : 230)
      .accessibilityLabel("Quota forecast")
      .accessibilityValue(
        "\(Int(forecast.remaining)) percent remaining. \(forecast.projectedUse == nil ? "Forecast unavailable" : forecast.daysEarly > 0 ? "Projected to run out early" : "On pace through reset"). \(range.label)."
      )
    }
    .id(range)
    .help(
      "The recorded line starts at the weekly limit (100% remaining) and stays connected through missing collector readings until now. Ideal pace spreads that limit evenly until reset. Forecast projects observed usage until the next reset."
    )
  }

  private func legend(_ title: String, color: Color, dashed: Bool) -> some View {
    HStack(spacing: 5) {
      Path { path in
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 16, y: 0))
      }
      .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 3] : []))
      .frame(width: 16, height: 1)
      Text(title).font(.system(size: compact ? 12 : 10)).foregroundStyle(muted)
    }
  }
}

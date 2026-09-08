import Charts
import SwiftUI

struct QuotaChart: View {
  let forecast: Forecast
  let samples: [QuotaSample]
  let color: Color
  var compact = false
  private var muted: Color { compact ? BurnTheme.quotaMuted : BurnTheme.muted }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 10 : 16) {
      HStack(spacing: 16) {
        legend("Recorded", color: color, dashed: false)
        if forecast.projectedUse != nil { legend("Forecast", color: color, dashed: true) }
        legend("Ideal pace", color: muted, dashed: true)
      }
      Chart {
        ForEach([0, 1], id: \.self) { index in
          LineMark(
            x: .value("Date", index == 0 ? forecast.start : forecast.reset),
            y: .value("Remaining", index == 0 ? 100 : 0), series: .value("Series", "Ideal pace")
          )
          .foregroundStyle(muted)
          .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        ForEach(Array(quotaSampleSegments(samples).enumerated()), id: \.offset) { index, segment in
          ForEach(Array(segment.enumerated()), id: \.offset) { _, sample in
            LineMark(
              x: .value("Date", sample.date), y: .value("Remaining", sample.remaining),
              series: .value("Series", "Recorded \(index)")
            )
            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.stepEnd)
            if segment.count == 1 {
              PointMark(x: .value("Date", sample.date), y: .value("Remaining", sample.remaining))
                .foregroundStyle(color).symbolSize(18)
            }
          }
        }
        if forecast.projectedUse != nil {
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
        RuleMark(x: .value("Latest reading", forecast.observedAt))
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
      .chartXScale(domain: forecast.start...forecast.reset)
      .chartYScale(domain: 0...105)
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
        AxisMarks(values: .stride(by: .day, count: compact ? 2 : 1)) { _ in
          AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(muted)
        }
      }
      .frame(height: compact ? 150 : 230)
      .accessibilityLabel("Quota forecast")
      .accessibilityValue(
        "\(Int(forecast.remaining)) percent remaining. \(forecast.projectedUse == nil ? "Forecast unavailable" : forecast.daysEarly > 0 ? "Projected to run out early" : "On pace through reset")."
      )
    }
    .help(
      "Ideal pace spreads the full quota evenly from the cycle start to the reset. Forecast projects your observed usage. Gaps indicate missing measurements."
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

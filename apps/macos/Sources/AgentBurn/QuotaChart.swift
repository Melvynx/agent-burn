import Charts
import SwiftUI

struct QuotaChart: View {
  let forecast: Forecast
  let samples: [QuotaSample]
  let color: Color
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 16) {
        legend("Recorded", color: color, dashed: false)
        legend("Forecast", color: color, dashed: true)
        legend("Even pace", color: BurnTheme.muted, dashed: true)
      }
      Chart {
        ForEach([0, 1], id: \.self) { index in
          LineMark(
            x: .value("Date", index == 0 ? forecast.start : forecast.reset),
            y: .value("Remaining", index == 0 ? 100 : 0), series: .value("Series", "Even pace")
          )
          .foregroundStyle(BurnTheme.muted.opacity(0.55))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
        }
        ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
          LineMark(
            x: .value("Date", sample.date), y: .value("Remaining", sample.remaining),
            series: .value("Series", "Recorded")
          )
          .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.5))
          .interpolationMethod(.stepEnd)
        }
        if forecast.projectedUse != nil {
          ForEach([0, 1], id: \.self) { index in
            LineMark(
              x: .value("Date", index == 0 ? forecast.observedAt : forecast.projectedEnd),
              y: .value("Remaining", index == 0 ? forecast.remaining : forecast.projectedRemaining),
              series: .value("Series", "Forecast")
            )
            .foregroundStyle(color.opacity(0.8))
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
          Text("Latest").font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(BurnTheme.elevated, in: Capsule())
        }
      }
      .chartXScale(domain: forecast.start...forecast.reset)
      .chartYScale(domain: 0...105)
      .chartYAxis {
        AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 5])).foregroundStyle(
            BurnTheme.line)
          AxisValueLabel {
            if let number = value.as(Int.self) {
              Text("\(number)%").foregroundStyle(BurnTheme.muted)
            }
          }
        }
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .day, count: compact ? 2 : 1)) { _ in
          AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(BurnTheme.muted)
        }
      }
      .frame(height: compact ? 170 : 230)
      .accessibilityLabel("Quota forecast")
      .accessibilityValue(
        "\(Int(forecast.remaining)) percent remaining. \(forecast.daysEarly > 0 ? "Projected to run out early" : "On pace through reset")."
      )
      if samples.count < 2 {
        Text("Your quota history builds as Agent Burn refreshes.")
          .font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
      }
    }
  }

  private func legend(_ title: String, color: Color, dashed: Bool) -> some View {
    HStack(spacing: 5) {
      Path { path in
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 16, y: 0))
      }
      .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 3] : []))
      .frame(width: 16, height: 1)
      Text(title).font(.system(size: 10)).foregroundStyle(BurnTheme.muted)
    }
  }
}

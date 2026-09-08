import SwiftUI

struct QuotaFreshnessView: View {
  let forecast: Forecast
  var error: String? = nil
  var compact = false

  var body: some View {
    TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 15)) { context in
      VStack(alignment: .leading, spacing: 4) {
        Label(
          forecast.freshnessLabel(at: context.date, failed: error != nil),
          systemImage: forecast.isFresh(at: context.date) && error == nil
            ? "checkmark.circle.fill" : "clock.badge.exclamationmark"
        )
        .foregroundStyle(
          compact
            ? BurnTheme.quotaMuted
            : forecast.isFresh(at: context.date) && error == nil ? .green : .orange)
        if !compact || !forecast.isFresh(at: context.date) || error != nil {
          Text(
            "Measured \(forecast.observedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second()))"
          )
          .foregroundStyle(compact ? BurnTheme.quotaMuted : .secondary)
        }
        if let error { Text(error).foregroundStyle(compact ? BurnTheme.quotaMuted : .secondary) }
      }
      .font(.caption)
      .accessibilityElement(children: .combine)
    }
  }
}

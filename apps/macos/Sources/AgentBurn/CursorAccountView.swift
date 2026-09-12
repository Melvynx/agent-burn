import SwiftUI

struct CursorAccount: Codable, Sendable {
  let billingCycleStartMs: Double?
  let billingCycleEndMs: Double?
  let includedLimitUSD: Double?
  let includedRemainingUSD: Double?
  let includedPercentUsed: Double?
  let includedSpendUSD: Double?
  let bonusSpendUSD: Double?
  let planSpendUSD: Double?
  let onDemandSpentUSD: Double?
  let onDemandLimitUSD: Double?
  let activeLimitUSD: Double?
  let activeRemainingUSD: Double?
  let activePercentUsed: Double?
  let grants: [CursorCreditGrant]
}

struct CursorCreditGrant: Codable, Sendable {
  let kind: String?
  let totalUSD: Double?
  let remainingUSD: Double?
  let expiresAtMs: Double?
}

struct CursorAccountView: View {
  @Environment(UsageStore.self) private var store
  let account: CursorAccount?
  let plan: SubscriptionAgent?
  @State private var range = QuotaChartRange.rtd
  private var promoForecast: Forecast? {
    cursorMeterForecast(
      account: account, now: store.quotaCheckDate, stored: store.forecast(for: "cursor"))
  }

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Label("Cursor " + (plan?.plan ?? "account"), systemImage: "creditcard")
            .font(.headline)
          Spacer()
          if let price = plan?.pricePerMonth {
            Text(currency(price) + " / month").foregroundStyle(.secondary)
          }
        }
        if let account {
          if let forecast = promoForecast, cursorHasPromotionalCredits(account) {
            promoMeter(forecast, account: account)
          } else {
            allowanceAndBilling(account)
            grantBars(account)
          }
          Text(
            "Plan allowance, promotional credits and API-equivalent usage are different balances. Missing billing amounts are not treated as zero."
          )
          .font(.caption).foregroundStyle(.secondary)
        } else {
          Text(
            "Account balances unavailable. Refresh with live data enabled to retrieve Cursor’s allowance, credits and billing cycle."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }.padding(12)
    }
  }

  @ViewBuilder private func promoMeter(_ forecast: Forecast, account: CursorAccount) -> some View {
    HStack(alignment: .top, spacing: 28) {
      QuotaSummary(
        forecast: forecast,
        samples: store.samples(for: "cursor", range: range, now: store.quotaCheckDate),
        now: store.quotaCheckDate,
        stale: !forecast.isFresh(at: store.quotaCheckDate)
          || store.quotaError(for: "cursor") != nil,
        staleHelp: store.quotaError(for: "cursor")
          ?? "Showing the last known reading. Update pending.",
        rates: store.blendRates(for: "cursor"),
        style: .promotionalCredits
      )
      .frame(width: 236, alignment: .leading)
      VStack(alignment: .trailing, spacing: 8) {
        QuotaChartRangePicker(range: $range)
        QuotaChart(
          forecast: forecast,
          samples: store.samples(for: "cursor", range: range, now: store.quotaCheckDate),
          color: BurnTheme.color(for: "cursor"),
          range: range, now: store.quotaCheckDate,
          resetLabel: QuotaMeterStyle.promotionalCredits.chartResetLabel
        )
        .id(range)
      }
    }
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Promotional credits").font(.subheadline.weight(.medium))
        Text("Expires " + date(account.grants.first { $0.kind == "promo" }?.expiresAtMs))
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        Text(account.activeRemainingUSD.map(currency) ?? "Unavailable")
          .font(.title2.weight(.semibold)).monospacedDigit()
        Text("remaining of " + (account.activeLimitUSD.map(currency) ?? "unknown"))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    if unusedIncludedWhileCreditsRemain(account) {
      Text("Included allowance is unused while promotional credits remain.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func allowanceAndBilling(_ account: CursorAccount) -> some View {
    HStack(alignment: .top, spacing: 28) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Included allowance").font(.subheadline.weight(.medium))
        Text(account.includedRemainingUSD.map(currency) ?? "Unavailable")
          .font(.title.weight(.semibold)).monospacedDigit()
        Text("remaining of " + (account.includedLimitUSD.map(currency) ?? "unknown"))
          .font(.caption).foregroundStyle(.secondary)
        if let used = account.includedPercentUsed {
          ProgressView(value: used, total: 100).tint(.purple)
          Text(
            used.formatted(.number.precision(.fractionLength(1)))
              + "% used · reported by Cursor"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      Divider()
      VStack(alignment: .leading, spacing: 8) {
        Text("Billing cycle").font(.subheadline.weight(.medium))
        Text("Renews " + date(account.billingCycleEndMs)).font(.subheadline)
        Text("Started " + date(account.billingCycleStartMs))
          .font(.caption).foregroundStyle(.secondary)
        Text("On-demand spend: " + (account.onDemandSpentUSD.map(currency) ?? "Not reported"))
          .font(.caption).foregroundStyle(.secondary)
        Text("On-demand limit: " + (account.onDemandLimitUSD.map(currency) ?? "Not reported"))
          .font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder private func grantBars(_ account: CursorAccount) -> some View {
    ForEach(Array(account.grants.enumerated()), id: \.offset) { _, grant in
      Divider()
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text(grant.kind == "promo" ? "Promotional credits" : "Account credits")
            .font(.subheadline.weight(.medium))
          Text("Expires " + date(grant.expiresAtMs)).font(.caption).foregroundStyle(
            .secondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 6) {
          Text(grant.remainingUSD.map(currency) ?? "Unavailable")
            .font(.title2.weight(.semibold)).monospacedDigit()
          Text("remaining of " + (grant.totalUSD.map(currency) ?? "unknown"))
            .font(.caption).foregroundStyle(.secondary)
          if let used = grantUsedPercent(grant) {
            ProgressView(value: used, total: 100)
            Text(
              used.formatted(.number.precision(.fractionLength(1))) + "% used"
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func date(_ milliseconds: Double?) -> String {
    guard let milliseconds else { return "Unavailable" }
    return Date(timeIntervalSince1970: milliseconds / 1000).formatted(
      date: .abbreviated, time: .omitted)
  }
}

private func unusedIncludedWhileCreditsRemain(_ account: CursorAccount) -> Bool {
  (account.includedPercentUsed ?? 0) == 0
    && account.grants.contains { ($0.remainingUSD ?? 0) > 0 }
}

private func grantUsedPercent(_ grant: CursorCreditGrant) -> Double? {
  guard let remaining = grant.remainingUSD, let total = grant.totalUSD, total > 0 else {
    return nil
  }
  return max(0, min(100, (total - remaining) / total * 100))
}

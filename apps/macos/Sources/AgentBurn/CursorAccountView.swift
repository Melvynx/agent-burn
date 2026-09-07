import SwiftUI

struct CursorAccount: Codable, Sendable {
  let billingCycleStartMs: Double?
  let billingCycleEndMs: Double?
  let includedLimitUSD: Double?
  let includedRemainingUSD: Double?
  let includedPercentUsed: Double?
  let onDemandSpentUSD: Double?
  let onDemandLimitUSD: Double?
  let grants: [CursorCreditGrant]
}

struct CursorCreditGrant: Codable, Sendable {
  let kind: String?
  let totalUSD: Double?
  let remainingUSD: Double?
  let expiresAtMs: Double?
}

struct CursorAccountView: View {
  let account: CursorAccount?
  let plan: SubscriptionAgent?

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
              }
            }
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

  private func date(_ milliseconds: Double?) -> String {
    guard let milliseconds else { return "Unavailable" }
    return Date(timeIntervalSince1970: milliseconds / 1000).formatted(
      date: .abbreviated, time: .omitted)
  }
}

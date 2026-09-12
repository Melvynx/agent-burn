import SwiftUI

struct ClaudeAccount: Codable, Sendable {
  let sessionUsedPercent: Double?
  let sessionResetsAtMs: Double?
  let weeklyUsedPercent: Double?
  let weeklyResetsAtMs: Double?
  var scoped: [ClaudeScopedLimit]
  let extraEnabled: Bool?
  let extraUsedUSD: Double?
  let extraLimitUSD: Double?
  let extraUsedPercent: Double?

  init(
    sessionUsedPercent: Double? = nil, sessionResetsAtMs: Double? = nil,
    weeklyUsedPercent: Double? = nil, weeklyResetsAtMs: Double? = nil,
    scoped: [ClaudeScopedLimit] = [], extraEnabled: Bool? = nil, extraUsedUSD: Double? = nil,
    extraLimitUSD: Double? = nil, extraUsedPercent: Double? = nil
  ) {
    self.sessionUsedPercent = sessionUsedPercent
    self.sessionResetsAtMs = sessionResetsAtMs
    self.weeklyUsedPercent = weeklyUsedPercent
    self.weeklyResetsAtMs = weeklyResetsAtMs
    self.scoped = scoped
    self.extraEnabled = extraEnabled
    self.extraUsedUSD = extraUsedUSD
    self.extraLimitUSD = extraLimitUSD
    self.extraUsedPercent = extraUsedPercent
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sessionUsedPercent = try container.decodeIfPresent(Double.self, forKey: .sessionUsedPercent)
    sessionResetsAtMs = try container.decodeIfPresent(Double.self, forKey: .sessionResetsAtMs)
    weeklyUsedPercent = try container.decodeIfPresent(Double.self, forKey: .weeklyUsedPercent)
    weeklyResetsAtMs = try container.decodeIfPresent(Double.self, forKey: .weeklyResetsAtMs)
    scoped = try container.decodeIfPresent([ClaudeScopedLimit].self, forKey: .scoped) ?? []
    extraEnabled = try container.decodeIfPresent(Bool.self, forKey: .extraEnabled)
    extraUsedUSD = try container.decodeIfPresent(Double.self, forKey: .extraUsedUSD)
    extraLimitUSD = try container.decodeIfPresent(Double.self, forKey: .extraLimitUSD)
    extraUsedPercent = try container.decodeIfPresent(Double.self, forKey: .extraUsedPercent)
  }
}

struct ClaudeScopedLimit: Codable, Sendable, Identifiable {
  let name: String
  let usedPercent: Double?
  let resetsAtMs: Double?
  var id: String { name }
}

struct ClaudeAccountView: View {
  let account: ClaudeAccount?
  let plan: SubscriptionAgent?

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Label(
            "Claude " + (plan?.plan ?? "account"), systemImage: "gauge.with.dots.needle.33percent"
          )
          .font(.headline)
          Spacer()
          if let price = plan?.pricePerMonth {
            Text(currency(price) + " / month").foregroundStyle(.secondary)
          }
        }
        if let account {
          HStack(alignment: .top, spacing: 28) {
            limitColumn(
              title: "Session remaining",
              used: account.sessionUsedPercent,
              caption: "of the 5-hour window",
              reset: account.sessionResetsAtMs)
            Divider()
            limitColumn(
              title: "Weekly remaining",
              used: account.weeklyUsedPercent,
              caption: "of the 7-day window",
              reset: account.weeklyResetsAtMs)
          }.fixedSize(horizontal: false, vertical: true)
          ForEach(account.scoped) { window in
            Divider()
            limitRow(
              title: window.name + " weekly",
              used: window.usedPercent,
              reset: window.resetsAtMs)
          }
          if showsExtra(account) {
            Divider()
            extraRow(account)
          }
          Text(
            "Session, weekly and extra-usage meters come from Claude’s live account. Daily spend below is API-equivalent token cost from local logs."
          )
          .font(.caption).foregroundStyle(.secondary)
        } else {
          Text(
            "Account limits unavailable. Refresh with live data enabled to retrieve Claude’s session, weekly and extra-usage meters."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }.padding(12)
    }
  }

  private func limitColumn(title: String, used: Double?, caption: String, reset: Double?)
    -> some View
  {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.subheadline.weight(.medium))
      Text(remainingLabel(used)).font(.title.weight(.semibold)).monospacedDigit()
      Text(caption).font(.caption).foregroundStyle(.secondary)
      if let used {
        ProgressView(value: used, total: 100).tint(.orange)
        Text(
          used.formatted(.number.precision(.fractionLength(1))) + "% used · reported by Claude"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Text("Resets " + date(reset, time: title.contains("Session"))).font(.caption)
        .foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func limitRow(title: String, used: Double?, reset: Double?) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.subheadline.weight(.medium))
        Text("Resets " + date(reset)).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 6) {
        Text(remainingLabel(used)).font(.title2.weight(.semibold)).monospacedDigit()
        if let used {
          ProgressView(value: used, total: 100).tint(.orange)
          Text(used.formatted(.number.precision(.fractionLength(1))) + "% used")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private func extraRow(_ account: ClaudeAccount) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 6) {
        Text("Extra usage").font(.subheadline.weight(.medium))
        Text(account.extraEnabled == true ? "Enabled this cycle" : "Reported by Claude")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 6) {
        Text(account.extraUsedUSD.map { extraRemaining(account, used: $0) } ?? "Unavailable")
          .font(.title2.weight(.semibold)).monospacedDigit()
        Text("remaining of " + (account.extraLimitUSD.map(currency) ?? "unknown"))
          .font(.caption).foregroundStyle(.secondary)
        if let used = extraUsedPercent(account) {
          ProgressView(value: used, total: 100)
          Text(used.formatted(.number.precision(.fractionLength(1))) + "% used")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private func date(_ milliseconds: Double?, time: Bool = false) -> String {
    guard let milliseconds else { return "Unavailable" }
    return Date(timeIntervalSince1970: milliseconds / 1000).formatted(
      date: .abbreviated, time: time ? .shortened : .omitted)
  }
}

func remainingLabel(_ used: Double?) -> String {
  guard let used else { return "Unavailable" }
  return max(0, min(100, 100 - used)).formatted(.number.precision(.fractionLength(1))) + "%"
}

func showsExtra(_ account: ClaudeAccount) -> Bool {
  account.extraEnabled == true || account.extraUsedUSD != nil || account.extraLimitUSD != nil
}

func extraUsedPercent(_ account: ClaudeAccount) -> Double? {
  if let used = account.extraUsedPercent { return max(0, min(100, used)) }
  guard let used = account.extraUsedUSD, let limit = account.extraLimitUSD, limit > 0 else {
    return nil
  }
  return max(0, min(100, used / limit * 100))
}

func extraRemaining(_ account: ClaudeAccount, used: Double) -> String {
  account.extraLimitUSD.map { currency(max(0, $0 - used)) } ?? currency(used) + " used"
}

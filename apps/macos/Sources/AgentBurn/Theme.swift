import SwiftUI

enum BurnTheme {
  static let background = Color(nsColor: .windowBackgroundColor)
  static let surface = Color(nsColor: .controlBackgroundColor)
  static let elevated = Color(nsColor: .quaternaryLabelColor).opacity(0.12)
  static let ink = Color.primary
  static let muted = Color.secondary
  static let accent = Color.accentColor
  static let green = Color.green
  static let line = Color(nsColor: .separatorColor).opacity(0.5)

  // Compact quota text and chart strokes must stay legible on menu material in both appearances.
  static let quotaMuted = adaptiveQuotaColor(
    light: NSColor(white: 0.38, alpha: 1), dark: NSColor(white: 0.68, alpha: 1))
  private static let quotaClaude = adaptiveQuotaColor(
    light: NSColor(red: 0.55, green: 0.26, blue: 0.02, alpha: 1), dark: .systemOrange)

  static func quotaColor(for agent: String) -> Color {
    agent == "claude"
      ? quotaClaude
      : adaptiveQuotaColor(
        light: NSColor(red: 0.04, green: 0.43, blue: 0.18, alpha: 1), dark: .systemGreen)
  }

  private static func adaptiveQuotaColor(light: NSColor, dark: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      })
  }

  static func color(for agent: String) -> Color {
    switch agent {
    case "codex": green
    case "claude": .orange
    case "cursor": .purple
    default: .blue
    }
  }
}

struct HarnessIcon: View {
  let agent: String
  var size: CGFloat = 32
  var body: some View {
    Group {
      if let image = BrandImages.images[agent] {
        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
      } else {
        Text(String(harnessName(agent).prefix(2))).font(
          .system(size: size * 0.4, weight: .semibold)
        )
        .foregroundStyle(.secondary)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

struct StatusBadge: View {
  let text: String
  var color: Color = BurnTheme.green
  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 5, height: 5)
      Text(text).font(.system(size: 11, weight: .medium))
    }
    .foregroundStyle(color)
    .padding(.horizontal, 9).padding(.vertical, 5)
    .background(color.opacity(0.09), in: Capsule())
  }
}

struct SectionLabel: View {
  let title: String
  var detail: String = ""
  var body: some View {
    HStack {
      Text(title).font(.system(size: 14, weight: .semibold))
      Spacer()
      if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(BurnTheme.muted) }
    }
  }
}

struct RefreshFooter: View {
  @Environment(UsageStore.self) private var store
  let source: String
  var compact = false
  var body: some View {
    HStack(spacing: 7) {
      Circle().fill(store.errors[source] == nil ? BurnTheme.green : BurnTheme.accent).frame(
        width: 5, height: 5)
      if let date = store.updated[source] {
        Text(store.errors[source] == nil ? "Updated" : "Last successful update")
        Text(date, style: .relative)
        Text("ago")
      } else if source == "summary", store.summary != nil {
        Text("Saved usage")
      } else if store.isLoading {
        Text("Updating usage…")
      } else {
        Text("Waiting for usage")
      }
      Spacer()
      Text(bundleVersionText())
        .monospacedDigit()
        .accessibilityLabel("App version")
      Button {
        Task { await store.refresh() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.plain).disabled(store.isLoading)
      .help("Refresh usage").accessibilityLabel("Refresh usage")
    }
    .font(.system(size: 11)).foregroundStyle(compact ? BurnTheme.quotaMuted : BurnTheme.muted)
  }
}

struct ReportNotice: View {
  let message: String
  var body: some View {
    Label(message, systemImage: "info.circle")
      .font(.system(size: 12)).foregroundStyle(BurnTheme.accent)
      .fixedSize(horizontal: false, vertical: true)
      .padding(12).frame(maxWidth: .infinity, alignment: .leading)
      .background(BurnTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
  }
}

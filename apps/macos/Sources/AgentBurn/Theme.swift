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
  var body: some View {
    HStack(spacing: 7) {
      Circle().fill(store.errors[source] == nil ? BurnTheme.green : BurnTheme.accent).frame(
        width: 5, height: 5)
      if store.isLoading {
        Text("Reading local usage…")
      } else if let date = store.updated[source] {
        Text(store.errors[source] == nil ? "Updated" : "Last successful update")
        Text(date, style: .relative)
        Text("ago")
      } else {
        Text("Waiting for usage")
      }
      Spacer()
      Button {
        Task { await store.refresh() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.plain).disabled(store.isLoading)
      .help("Refresh usage").accessibilityLabel("Refresh usage")
    }
    .font(.system(size: 11)).foregroundStyle(BurnTheme.muted)
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

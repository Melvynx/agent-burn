import SwiftUI

struct MenuPopover: View {
  @Environment(UsageStore.self) private var store
  @Environment(\.openWindow) private var openWindow
  private var tab: String { store.selection }

  var body: some View {
    @Bindable var store = store
    VStack(spacing: 0) {
      HStack {
        Label("Agent Burn", systemImage: "flame.fill").font(.system(size: 13, weight: .semibold))
          .foregroundStyle(BurnTheme.ink)
        Spacer()
        SettingsLink { Image(systemName: "gearshape") }
          .buttonStyle(.plain).foregroundStyle(BurnTheme.muted).help("Settings")
          .accessibilityLabel("Settings")
          .frame(minWidth: 24, minHeight: 24)
      }.padding(.horizontal, 22).padding(.top, 19).padding(.bottom, 17)
      HarnessTabs(selection: $store.selection, compact: true)
        .padding(4)
        .padding(.horizontal, 18).padding(.bottom, 20)
      ScrollView {
        Group {
          if tab == "summary" {
            OverviewView(compact: true)
          } else if ["codex", "claude"].contains(tab) {
            HarnessView(agent: tab, compact: true)
          } else {
            SourceUsageView(agent: tab, compact: true)
          }
        }.padding(.horizontal, 22).padding(.bottom, 20)
      }.frame(height: ["codex", "claude"].contains(tab) ? 440 : 520)
      Rectangle().fill(BurnTheme.line).frame(height: 1)
      VStack(spacing: 10) {
        RefreshFooter(source: ["codex", "claude"].contains(tab) ? tab : "summary", compact: true)
        HStack {
          Button {
            store.selection = tab
            openWindow(id: "overview")
            NSApp.activate(ignoringOtherApps: true)
          } label: {
            HStack {
              Text("Open dashboard")
              Spacer()
              Image(systemName: "arrow.up.right")
            }.font(.system(size: 12, weight: .medium))
              .padding(.horizontal, 12).padding(.vertical, 10)
              .background(BurnTheme.elevated, in: RoundedRectangle(cornerRadius: 7))
          }.buttonStyle(.plain)
          Button {
            NSApp.terminate(nil)
          } label: {
            Image(systemName: "power")
          }
          .buttonStyle(.plain).foregroundStyle(BurnTheme.muted).help("Quit Agent Burn")
          .accessibilityLabel("Quit Agent Burn").padding(.leading, 8)
        }
      }.padding(18)
    }
    .frame(width: 440).background(.regularMaterial).foregroundStyle(BurnTheme.ink)
  }

}

struct DashboardView: View {
  @Environment(UsageStore.self) private var store
  var body: some View {
    @Bindable var store = store
    VStack(spacing: 0) {
      ScrollView {
        NativeUsageView(agent: store.selection == "summary" ? nil : store.selection)
          .padding(24).frame(maxWidth: 1280).frame(maxWidth: .infinity)
      }
      Divider()
      RefreshFooter(source: "summary").padding(.horizontal, 20).padding(.vertical, 9)
    }
    .frame(minWidth: 900, minHeight: 650)
    .background(BurnTheme.background)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        QuotaSourceMenu()
      }
      ToolbarItem(placement: .principal) {
        HarnessTabs(selection: $store.selection)
          .padding(.horizontal, 6)
          .fixedSize(horizontal: true, vertical: false)
      }
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          Task { await store.refreshAll() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .help("Refresh usage and live quotas")
        SettingsLink { Label("Settings", systemImage: "gearshape") }.help("Settings")
      }
    }
  }
}

struct HarnessTabs: View {
  @Environment(UsageStore.self) private var store
  @Binding var selection: String
  var compact = false
  private var extra: [String] {
    store.knownAgents.filter { !["codex", "claude", "cursor"].contains($0) }
  }
  var body: some View {
    HStack(spacing: 8) {
      Picker("Harness", selection: $selection) {
        Text("General").tag("summary")
        Text("Codex").tag("codex")
        Text("Claude").tag("claude")
        Text("Cursor").tag("cursor")
      }.pickerStyle(.segmented).labelsHidden()
      if !compact, !extra.isEmpty {
        Menu(extra.contains(selection) ? harnessName(selection) : "More") {
          ForEach(extra, id: \.self) { agent in Button(harnessName(agent)) { selection = agent } }
        }.fixedSize()
      }
    }.controlSize(.regular)
  }

}

struct QuotaSourceMenu: View {
  @Environment(UsageStore.self) private var store
  var body: some View {
    @Bindable var store = store
    Menu {
      ForEach(QuotaSource.allCases) { source in
        Button {
          store.quotaSource = source
        } label: {
          HStack {
            Text(source.label)
            Spacer()
            if let remaining = remainingQuota(
              for: source, forecast: store.forecast(for: source.rawValue),
              cursorAccount: store.summary?.cursorAccount)
            {
              Text(menuBarQuotaText(remaining))
            }
          }
        }
      }
    } label: {
      Text(
        menuBarQuotaText(
          store.remainingPercent, stale: store.quotaIsStale(at: store.quotaCheckDate))
      )
      .monospacedDigit()
      .fontWeight(.medium)
      .fixedSize()
    }
    .menuIndicator(.visible)
    .fixedSize()
    .id(store.remainingPercent ?? -1)
    .help("Quota shown in the menu bar")
    .accessibilityLabel(
      "\(store.quotaSource.label) \(menuBarQuotaText(store.remainingPercent))")
  }
}

struct QuotaSourceSettings: View {
  @Environment(UsageStore.self) private var store
  var body: some View {
    @Bindable var store = store
    Section("Menu bar quota") {
      Picker("Show remaining", selection: $store.quotaSource) {
        ForEach(QuotaSource.allCases) { source in
          Text(source.label).tag(source)
        }
      }
      Text(
        "The flame in the menu bar and the window toolbar show this remaining percentage. Codex uses the live weekly account meter, Claude uses its weekly limit, and Cursor uses promotional credits when those are the active balance, otherwise the included allowance."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
  }
}

struct SettingsView: View {
  @Environment(UsageStore.self) private var store
  var body: some View {
    @Bindable var store = store
    Form {
      LoginItemSettings()
      AppearanceSettings()
      QuotaSourceSettings()
      UpdateSettings()
      Section("Data source") {
        TextField("CLI executable", text: $store.customPath, prompt: Text("Bundled agent-burn"))
          .help("Absolute path to the native agent-burn executable")
        Button("Choose executable…") {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = false
          panel.allowsMultipleSelection = false
          panel.message = "Choose the native agent-burn executable."
          if panel.runModal() == .OK, let url = panel.url { store.customPath = url.path }
        }
        Toggle("Use cached pricing and limits", isOn: $store.offline)
        Text(
          "Cached mode skips live subscription requests. Otherwise, the CLI may contact pricing and harness providers."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Log folders") {
        TextField("Codex homes", text: $store.codexHomes, axis: .vertical)
          .lineLimit(2...4).font(.system(.caption, design: .monospaced))
        Text(
          "Comma-separated Codex folders. The normal ~/.codex folder is included alongside the launching profile. Sessions and archived sessions are read by the CLI."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Refresh") {
        Picker("Automatically refresh", selection: $store.refreshMinutes) {
          Text("Every minute").tag(1)
          Text("Every 5 minutes").tag(5)
          Text("Every 15 minutes").tag(15)
          Text("Every 30 minutes").tag(30)
        }
        Button(store.isLoading ? "Refreshing…" : "Apply and refresh") {
          Task { await store.refreshAll() }
        }
      }
      QuotaCollectionSettings()
    }
    .formStyle(.grouped).padding(12).frame(width: 560, height: 520)
  }
}

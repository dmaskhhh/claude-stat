import SwiftUI

let COLLAPSED_H: CGFloat = 108
let EXPANDED_H:  CGFloat = 390

struct HUDView: View {
    @EnvironmentObject var store: StatsStore
    @State private var expanded = false
    @State private var hovering = false
    var onToggle: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            collapsedContent
            if expanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: 110)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(hovering ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: hovering)
        .overlay(alignment: .bottom) {
            if hovering && !expanded {
                Text("▾ tap to expand")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 5)
                    .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                expanded.toggle()
            }
            onToggle(expanded)
        }
        .contextMenu { contextMenuItems }
    }

    // MARK: Collapsed — two progress bars (real-time from Claude Code)

    var collapsedContent: some View {
        VStack(spacing: 9) {
            if store.hasLiveData {
                UsageBar(
                    label: "5h Session",
                    pct: store.fiveHourPct,
                    subtitle: store.resetLabel(for: store.fiveHourReset)
                )
                UsageBar(
                    label: "7-Day",
                    pct: store.sevenDayPct,
                    subtitle: store.resetLabel(for: store.sevenDayReset)
                )
            } else {
                // No live data yet — shown before first Claude Code response
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Waiting for Claude Code…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text("Usage data appears after your first message")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Expanded — historical detail

    var expandedContent: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.25)
            detailSection
        }
    }

    @State private var tab: Tab = .today
    enum Tab: String, CaseIterable { case today = "1 Day"; case week = "7 Days" }

    var detailSection: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 7).padding(.vertical, 6)

            let s = tab == .today ? store.todayStats : store.weekStats
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                MiniCard(icon: "bubble.left.fill", label: "Msgs",     value: fmt(s.messages),  color: .blue)
                MiniCard(icon: "hammer.fill",      label: "Tools",    value: fmt(s.toolCalls), color: .orange)
                MiniCard(icon: "bolt.fill",        label: "Tokens",   value: fmtTok(s.tokens), color: .purple)
                MiniCard(icon: "terminal.fill",    label: "Sessions", value: "\(s.sessions)",  color: .teal)
            }
            .padding(.horizontal, 7).padding(.bottom, 6)

            if !store.recentDays.isEmpty {
                Divider().opacity(0.2).padding(.horizontal, 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text("14-day tokens")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 10).padding(.top, 5)
                    SparklineView(values: store.recentDays.map(\.tokens), color: .purple)
                        .frame(height: 24)
                        .padding(.horizontal, 10)
                }
            }

            HStack(spacing: 3) {
                if store.activeSessions > 0 {
                    Circle().fill(.green).frame(width: 4, height: 4)
                    Text("\(store.activeSessions) active · ").font(.system(size: 8)).foregroundStyle(.secondary)
                }
                Text("thru \(store.lastComputedDate)").font(.system(size: 8)).foregroundStyle(.secondary)
                Spacer()
                Text(relTime(store.lastUpdated)).font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.top, 5).padding(.bottom, 8)
        }
    }

    // MARK: Context menu

    @ViewBuilder var contextMenuItems: some View {
        Button("Refresh") { store.load(); store.countSessions() }
        Divider()
        Button("Quit ClaudeStat") { NSApp.terminate(nil) }
    }

    // MARK: Formatters

    func fmt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n)/1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n)/1_000) }
        return "\(n)"
    }
    func fmtTok(_ n: Int) -> String { n == 0 ? "–" : fmt(n) }
    func relTime(_ d: Date) -> String {
        let s = Int(-d.timeIntervalSinceNow)
        if s < 60 { return "just now" }; if s < 3600 { return "\(s/60)m ago" }; return "\(s/3600)h ago"
    }
}

// MARK: - Progress bar (real usage percentage from Claude Code)

struct UsageBar: View {
    let label: String
    let pct: Double        // 0–100
    let subtitle: String

    var fraction: Double { min(1.0, pct / 100.0) }
    var color: Color {
        if pct >= 75 { return .green }
        if pct >= 50 { return .blue }
        if pct >= 25 { return .purple }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 5)
                    Capsule().fill(color)
                        .frame(width: max(3, geo.size.width * fraction), height: 5)
                        .animation(.easeOut(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 5)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Mini stat card

struct MiniCard: View {
    let icon: String; let label: String; let value: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color)
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(6)
    }
}

// MARK: - Sparkline

struct SparklineView: View {
    let values: [Int]; let color: Color
    var body: some View {
        let maxVal = values.max() ?? 1
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    let h = maxVal > 0 ? max(2, CGFloat(v)/CGFloat(maxVal)*geo.size.height) : 2
                    RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.55)).frame(height: h)
                }
            }
        }
    }
}

typealias ContentView = HUDView

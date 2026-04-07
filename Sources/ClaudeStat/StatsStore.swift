import Foundation
import AppKit

// MARK: - hud-cache.json (real-time data from Claude Code statusline hook)

struct RateWindow: Codable {
    let usedPercentage: Double?
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt       = "resets_at"
    }
}

struct RateLimits: Codable {
    let fiveHour: RateWindow?
    let sevenDay: RateWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct HudCache: Codable {
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

// MARK: - stats-cache.json (historical daily data)

struct DailyActivity: Codable {
    let date: String
    let messageCount: Int
    let sessionCount: Int
    let toolCallCount: Int
}

struct DailyModelTokens: Codable {
    let date: String
    let tokensByModel: [String: Int]
    var totalTokens: Int { tokensByModel.values.reduce(0, +) }
}

struct StatsCache: Codable {
    let version: Int
    let lastComputedDate: String?
    let dailyActivity: [DailyActivity]
    let dailyModelTokens: [DailyModelTokens]
}

struct PeriodStats {
    var messages: Int = 0
    var sessions: Int = 0
    var toolCalls: Int = 0
    var tokens: Int = 0
}

struct DayPoint: Identifiable {
    let id = UUID()
    let date: String
    let tokens: Int
    let messages: Int
}

// MARK: - Store

class StatsStore: ObservableObject {
    // ── Real-time rate limits (from hud-cache.json, written by statusline hook) ──
    @Published var fiveHourPct:  Double = 0   // 0–100
    @Published var sevenDayPct:  Double = 0
    @Published var fiveHourReset: Date?
    @Published var sevenDayReset: Date?
    @Published var hasLiveData  = false

    // ── Historical detail (from stats-cache.json) ────────────────────────────────
    @Published var todayStats        = PeriodStats()
    @Published var weekStats         = PeriodStats()
    @Published var recentDays: [DayPoint] = []
    @Published var lastUpdated       = Date()
    @Published var lastComputedDate  = "-"
    @Published var activeSessions    = 0

    var onUpdate: (() -> Void)?

    private let hudCacheURL  = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/hud-cache.json")
    private let statsURL     = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/stats-cache.json")
    private let sessionsDir  = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/sessions")

    private var fdHud: Int32 = -1
    private var fdStats: Int32 = -1
    private var sourceHud: DispatchSourceFileSystemObject?
    private var sourceStats: DispatchSourceFileSystemObject?
    private var timer: Timer?

    init() {
        load()
        watchFile(url: hudCacheURL,   fd: &fdHud,   source: &sourceHud)
        watchFile(url: statsURL,      fd: &fdStats,  source: &sourceStats)
        startTimer()
    }

    // MARK: Load

    func load() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.loadHudCache()
            self?.loadStatsCache()
            DispatchQueue.main.async {
                self?.countSessions()
                self?.lastUpdated = Date()
                self?.onUpdate?()
            }
        }
    }

    private func loadHudCache() {
        guard let data  = try? Data(contentsOf: hudCacheURL),
              let cache = try? JSONDecoder().decode(HudCache.self, from: data),
              let rl    = cache.rateLimits
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasLiveData = true

            if let w = rl.fiveHour {
                self.fiveHourPct   = w.usedPercentage ?? 0
                self.fiveHourReset = w.resetsAt.map { Date(timeIntervalSince1970: $0) }
            }
            if let w = rl.sevenDay {
                self.sevenDayPct   = w.usedPercentage ?? 0
                self.sevenDayReset = w.resetsAt.map { Date(timeIntervalSince1970: $0) }
            }
        }
    }

    private func loadStatsCache() {
        guard let data  = try? Data(contentsOf: statsURL),
              let cache = try? JSONDecoder().decode(StatsCache.self, from: data)
        else { return }

        let weekStart = isoDate(Calendar.current.date(byAdding: .day, value: -6, to: Date())!)

        var tokMap: [String: Int] = [:]
        for t in cache.dailyModelTokens { tokMap[t.date] = t.totalTokens }

        // Use the most recent date that has activity data, not necessarily today
        let lastDay = cache.dailyActivity.map(\.date).max() ?? ""

        var td = PeriodStats(), wk = PeriodStats()
        for a in cache.dailyActivity {
            if a.date == lastDay {
                td.messages = a.messageCount; td.sessions = a.sessionCount; td.toolCalls = a.toolCallCount
            }
            if a.date >= weekStart {
                wk.messages += a.messageCount; wk.sessions += a.sessionCount; wk.toolCalls += a.toolCallCount
            }
        }

        td.tokens = tokMap[lastDay] ?? 0
        for (date, tok) in tokMap where date >= weekStart { wk.tokens += tok }

        let allDates = Set(cache.dailyActivity.map(\.date)).union(Set(tokMap.keys)).sorted().suffix(14)
        let days = allDates.map { date -> DayPoint in
            let a = cache.dailyActivity.first { $0.date == date }
            return DayPoint(date: date, tokens: tokMap[date] ?? 0, messages: a?.messageCount ?? 0)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.todayStats       = td
            self.weekStats        = wk
            self.recentDays       = days
            self.lastComputedDate = cache.lastComputedDate ?? "-"
        }
    }

    func countSessions() {
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil)) ?? []
        DispatchQueue.main.async { self.activeSessions = files.filter { $0.pathExtension == "json" }.count }
    }

    // MARK: File watcher

    private func watchFile(url: URL, fd: inout Int32, source: inout DispatchSourceFileSystemObject?) {
        let openFd = open(url.path, O_EVTONLY)
        fd = openFd
        guard openFd != -1 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: openFd, eventMask: [.write, .rename, .delete], queue: .global(qos: .background))
        src.setEventHandler { [weak self] in self?.load() }
        src.setCancelHandler { close(openFd) }
        src.resume()
        source = src
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.load() }
    }

    deinit {
        sourceHud?.cancel()
        sourceStats?.cancel()
        timer?.invalidate()
    }

    // MARK: Reset time helpers

    func resetLabel(for date: Date?) -> String {
        guard let date else { return "" }
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "resetting…" }
        let h = Int(diff) / 3600
        let m = (Int(diff) % 3600) / 60
        if h > 0 { return "resets in \(h)h \(m)m" }
        return "resets in \(m)m"
    }

    private func isoDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
}

import Foundation

/// 性能埋点分类。落盘用字符串原始值，方便直接 grep JSONL。
enum PerfCategory: String, Codable, CaseIterable, Sendable {
    case page = "PAGE"
    case api = "API"
    case sync = "SYNC"
    case custom = "CUSTOM"

    var symbol: String {
        switch self {
        case .page: return "▦"
        case .api: return "⇄"
        case .sync: return "↻"
        case .custom: return "•"
        }
    }
}

/// 一次计时结果。start + durationMs 即可还原完整时间区间。
struct PerfSpan: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let category: PerfCategory
    let start: Date
    let durationMs: Double
    let success: Bool
    let detail: String?

    var end: Date { start.addingTimeInterval(durationMs / 1000) }

    /// 毫秒展示：小于 10ms 保留 1 位，否则取整，避免统计表里一堆小数。
    var durationText: String {
        durationMs < 10
            ? String(format: "%.1f ms", durationMs)
            : "\(Int(durationMs.rounded())) ms"
    }
}

/// 按名称聚合后的统计。性能面板直接消费它排序。
struct PerfStat: Sendable, Identifiable {
    let name: String
    let category: PerfCategory
    let count: Int
    let avgMs: Double
    let p50Ms: Double
    let p95Ms: Double
    let maxMs: Double
    let lastMs: Double
    let lastAt: Date
    let failCount: Int

    var id: String { "\(category.rawValue)/\(name)" }

    /// 被判定为慢调用的阈值：页面 400ms，接口/同步 800ms。
    var isSlow: Bool {
        let threshold: Double = category == .page ? 400 : 800
        return avgMs >= threshold || p95Ms >= threshold * 2
    }
}

/// 性能追踪中心。
///
/// - 所有写入经 NSLock 串行化，actor（HealthKitService）与主线程都可安全调用。
/// - 内存保留最近 3000 条 span，磁盘同步写 JSONL（Documents/healthy-perf.jsonl），
///   与业务日志 AppLog 分开，避免性能埋点把调试日志冲掉。
/// - 不做网络上传，数据只在手机本地，可从性能面板导出。
final class PerformanceTrace: @unchecked Sendable {
    static let shared = PerformanceTrace()

    /// 一次计时的句柄，值类型、Sendable，可安全跨 await / actor 边界传递。
    struct Token: Sendable {
        let id: UUID
        let name: String
        let category: PerfCategory
        let start: Date
        let detail: String?
    }

    private let lock = NSLock()
    private var spans: [PerfSpan] = []
    private let maxSpans = 3000
    private let maxFileBytes = 2 * 1024 * 1024
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// 待结束的页面切换计时：由 TabView 选择时 begin，目标页面 onAppear 时结束。
    private var pendingPageSwitch: (token: Token, target: String)?

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = documents.appendingPathComponent("healthy-perf.jsonl", isDirectory: false)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
    }

    // MARK: - 手动计时

    /// 开始一次计时，返回句柄；调用 end(_:) 结束。
    func begin(
        _ name: String,
        category: PerfCategory,
        detail: String? = nil
    ) -> Token {
        Token(
            id: UUID(),
            name: name,
            category: category,
            start: Date(),
            detail: detail
        )
    }

    /// 结束计时。未传 detail 时沿用 begin 时的备注。
    @discardableResult
    func end(
        _ token: Token,
        success: Bool = true,
        detail: String? = nil
    ) -> Double {
        let durationMs = Date().timeIntervalSince(token.start) * 1000
        record(
            token.name,
            category: token.category,
            durationMs: durationMs,
            start: token.start,
            success: success,
            detail: detail ?? token.detail
        )
        return durationMs
    }

    /// 直接记录已知耗时（页面首帧等场景用）。
    func record(
        _ name: String,
        category: PerfCategory,
        durationMs: Double,
        start: Date = Date(),
        success: Bool = true,
        detail: String? = nil
    ) {
        let span = PerfSpan(
            id: UUID(),
            name: name,
            category: category,
            start: start,
            durationMs: max(0, durationMs),
            success: success,
            detail: detail
        )
        lock.lock()
        defer { lock.unlock() }
        spans.append(span)
        if spans.count > maxSpans {
            spans.removeFirst(spans.count - maxSpans)
        }
        appendToDisk(span)
    }

    // MARK: - 闭包计时

    /// 同步闭包计时；闭包抛错时记 success=false 并原样抛出。
    func measure<T>(
        _ name: String,
        category: PerfCategory,
        detail: String? = nil,
        work: () throws -> T
    ) rethrows -> T {
        let token = begin(name, category: category, detail: detail)
        do {
            let value = try work()
            end(token)
            return value
        } catch {
            end(token, success: false, detail: String(describing: error))
            throw error
        }
    }

    /// 异步闭包计时；网络请求、HealthKit 查询、同步流程都走这里。
    func measure<T>(
        _ name: String,
        category: PerfCategory,
        detail: String? = nil,
        work: () async throws -> T
    ) async rethrows -> T {
        let token = begin(name, category: category, detail: detail)
        do {
            let value = try await work()
            end(token)
            return value
        } catch {
            end(token, success: false, detail: String(describing: error))
            throw error
        }
    }

    // MARK: - 页面切换

    /// TabView 切换时调用，记录目标页名；目标页 onAppear 时由 endPageSwitchIfNeeded 收尾。
    func beginPageSwitch(to target: String) {
        let token = begin("\(target) · 切换耗时", category: .page)
        lock.lock()
        pendingPageSwitch = (token, target)
        lock.unlock()
    }

    /// 页面出现时结算等待中的切换计时。名称不一致（如用户快速连点）则丢弃旧计时。
    @discardableResult
    func endPageSwitchIfNeeded(pageName: String) -> Bool {
        lock.lock()
        let pending = pendingPageSwitch
        pendingPageSwitch = nil
        lock.unlock()
        guard let pending, pending.target == pageName else { return false }
        end(pending.token)
        return true
    }

    // MARK: - 读取 / 维护

    func snapshot() -> [PerfSpan] {
        lock.lock()
        defer { lock.unlock() }
        return spans
    }

    /// 聚合统计，按平均耗时降序，供性能面板排序展示。
    func stats() -> [PerfStat] {
        let all = snapshot()
        var groups: [String: (category: PerfCategory, values: [Double], fails: Int)] = [:]
        for span in all {
            let key = "\(span.category.rawValue)/\(span.name)"
            var group = groups[key] ?? (span.category, [], 0)
            group.values.append(span.durationMs)
            if !span.success { group.fails += 1 }
            groups[key] = group
        }
        return groups.map { key, group in
            let sorted = group.values.sorted()
            let name = key.split(separator: "/", maxSplits: 1).dropFirst().joined(separator: "/")
            let last = all.last(where: { "\($0.category.rawValue)/\($0.name)" == key })
            return PerfStat(
                name: name,
                category: group.category,
                count: sorted.count,
                avgMs: sorted.reduce(0, +) / Double(sorted.count),
                p50Ms: percentile(sorted, 0.50),
                p95Ms: percentile(sorted, 0.95),
                maxMs: sorted.last ?? 0,
                lastMs: last?.durationMs ?? 0,
                lastAt: last?.start ?? .distantPast,
                failCount: group.fails
            )
        }
        .sorted { $0.avgMs > $1.avgMs }
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count) - 1) * p)))
        return sorted[index]
    }

    /// 导出为可读文本，供系统分享面板发出去。
    func exportText() -> String {
        let header = "name\tcategory\tstart\tdurationMs\tsuccess\tdetail"
        let rows = snapshot().map { span in
            [
                span.name,
                span.category.rawValue,
                span.start.formatted(.iso8601),
                String(format: "%.2f", span.durationMs),
                span.success ? "1" : "0",
                span.detail ?? ""
            ]
            .joined(separator: "\t")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    var fileSizeDescription: String {
        lock.lock()
        defer { lock.unlock() }
        guard let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber else {
            return "—"
        }
        return size.intValue >= 1024
            ? String(format: "%.1f KB", size.doubleValue / 1024)
            : "\(size.intValue) B"
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        spans.removeAll()
        pendingPageSwitch = nil
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }

    var logFilePath: String { fileURL.path }

    // MARK: - 磁盘

    private func loadFromDisk() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            return
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(maxSpans)
        spans = lines.compactMap { line in
            try? decoder.decode(PerfSpan.self, from: Data(line.utf8))
        }
        if text.utf8.count > maxFileBytes { rewriteDiskFromMemory() }
    }

    private func appendToDisk(_ span: PerfSpan) {
        guard var data = try? encoder.encode(span) else { return }
        data.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
        if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber,
           size.intValue > maxFileBytes {
            rewriteDiskFromMemory()
        }
    }

    private func rewriteDiskFromMemory() {
        var data = Data()
        for span in spans {
            guard var line = try? encoder.encode(span) else { continue }
            line.append(0x0A)
            data.append(line)
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// 全局便捷函数，避免每个埋点都写 `PerformanceTrace.shared`。
func perfMeasure<T>(
    _ name: String,
    category: PerfCategory,
    detail: String? = nil,
    work: () throws -> T
) rethrows -> T {
    try PerformanceTrace.shared.measure(name, category: category, detail: detail, work: work)
}

func perfMeasure<T>(
    _ name: String,
    category: PerfCategory,
    detail: String? = nil,
    work: () async throws -> T
) async rethrows -> T {
    try await PerformanceTrace.shared.measure(name, category: category, detail: detail, work: work)
}

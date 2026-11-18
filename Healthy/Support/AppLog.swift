import Foundation

/// 日志级别。用字符串原始值落盘，方便直接把 .jsonl 拖出来 grep。
enum AppLogLevel: String, Codable, CaseIterable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    var symbol: String {
        switch self {
        case .debug: return "•"
        case .info: return "i"
        case .warning: return "!"
        case .error: return "✕"
        }
    }
}

/// 一条日志。时间用 ISO8601 带时区落盘，避免真机 / 模拟器跨时区比对时歧义。
struct AppLogEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let time: Date
    let level: AppLogLevel
    let category: String
    let message: String

    /// 列表里显示的一行摘要（时间只到秒）。
    var shortTime: String {
        Self.shortFormatter.string(from: time)
    }

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()
}

/// App 内置日志中心。
///
/// - 内存保留最近 2000 条，磁盘同步写 JSONL（Documents/healthy-debug.jsonl），
///   App 被杀掉 / 重装前都能从手机里导出。
/// - 所有写入经 NSLock 串行化，HealthKitService 是 actor、UI 在 main，
///   两边都能直接调，不需要切线程。
/// - 不做网络上传，只在手机本地。
final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    private let lock = NSLock()
    private var entries: [AppLogEntry] = []
    private let maxEntries = 2000
    private let maxFileBytes = 2 * 1024 * 1024
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = documents.appendingPathComponent("healthy-debug.jsonl", isDirectory: false)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
    }

    // MARK: - 写入

    func debug(_ category: String, _ message: String) {
        write(.debug, category: category, message: message)
    }

    func info(_ category: String, _ message: String) {
        write(.info, category: category, message: message)
    }

    func warning(_ category: String, _ message: String) {
        write(.warning, category: category, message: message)
    }

    func error(_ category: String, _ message: String) {
        write(.error, category: category, message: message)
    }

    private func write(_ level: AppLogLevel, category: String, message: String) {
        let entry = AppLogEntry(
            id: UUID(), time: Date(), level: level, category: category, message: message
        )
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        appendToDisk(entry)
    }

    // MARK: - 读取 / 维护

    /// UI 用的快照；返回新数组，调用方可以自由过滤排序而不持锁。
    func snapshot() -> [AppLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// 导出为可读文本，供系统分享面板发出去。
    func exportText() -> String {
        snapshot().map { entry in
            "\(entry.time.formatted(.iso8601)) [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
        }
        .joined(separator: "\n")
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
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }

    /// 供诊断按钮打印文件位置，方便 `xcrun devicectl` 拉文件。
    var logFilePath: String { fileURL.path }

    // MARK: - 磁盘

    private func loadFromDisk() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            return
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(maxEntries)
        entries = lines.compactMap { line in
            try? decoder.decode(AppLogEntry.self, from: Data(line.utf8))
        }
        trimFileIfNeeded(text: text)
    }

    private func appendToDisk(_ entry: AppLogEntry) {
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
        // 文件超过 2 MB 时只保留内存里的 2000 条，避免长期占用手机空间。
        if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber,
           size.intValue > maxFileBytes {
            rewriteDiskFromMemory()
        }
    }

    private func rewriteDiskFromMemory() {
        var data = Data()
        for entry in entries {
            guard var line = try? encoder.encode(entry) else { continue }
            line.append(0x0A)
            data.append(line)
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func trimFileIfNeeded(text: String) {
        let bytes = text.utf8.count
        guard bytes > maxFileBytes else { return }
        rewriteDiskFromMemory()
    }

}

/// 全局便捷函数，避免每个埋点都写 `AppLog.shared`。
func appLog(_ level: AppLogLevel = .info, _ category: String, _ message: String) {
    switch level {
    case .debug: AppLog.shared.debug(category, message)
    case .info: AppLog.shared.info(category, message)
    case .warning: AppLog.shared.warning(category, message)
    case .error: AppLog.shared.error(category, message)
    }
}

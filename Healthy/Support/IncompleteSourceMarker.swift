import Foundation

/// 手动标记「某类数据不全」的持久化。
///
/// 标记按 dayKey 存储，只影响对应日期的评分，不污染历史日期与全局评分口径。
/// 存储格式：UserDefaults 中的 `[dayKey: [MetricSource.rawValue]]` JSON。
/// 之所以不用位掩码：UserDefaults 读写 JSON 更直观，且 MetricSource 增删时无需重编码。
enum IncompleteSourceMarker {
    /// UserDefaults 键名。
    private static let key = "healthy.scoring.manualIncompleteSources"

    /// 读取指定日期被手动标记为不全的数据源集合。
    /// - Parameter dayKey: 日期键（yyyy-MM-dd）。
    /// - Returns: 被标记的数据源集合；无标记或数据损坏时为空集合。
    static func markedSources(for dayKey: String) -> Set<MetricSource> {
        guard let values = readAll()[dayKey] else { return [] }
        return Set(values.compactMap(MetricSource.init(rawValue:)))
    }

    /// 判断指定日期的某类数据是否被手动标记为不全。
    /// - Parameters:
    ///   - source: 数据类别。
    ///   - dayKey: 日期键。
    static func isMarked(_ source: MetricSource, dayKey: String) -> Bool {
        markedSources(for: dayKey).contains(source)
    }

    /// 设置或取消指定日期某类数据的不全标记。
    /// - Parameters:
    ///   - source: 数据类别。
    ///   - marked: true 表示标记为不全，false 表示取消标记。
    ///   - dayKey: 日期键。
    static func set(_ source: MetricSource, marked: Bool, dayKey: String) {
        var all = readAll()
        var values = Set(all[dayKey] ?? [])
        if marked {
            values.insert(source.rawValue)
        } else {
            values.remove(source.rawValue)
        }
        if values.isEmpty {
            all.removeValue(forKey: dayKey)
        } else {
            all[dayKey] = values.sorted()
        }
        writeAll(all)
    }

    /// 切换指定日期某类数据的不全标记。
    /// - Returns: 切换后是否处于「已标记」状态。
    @discardableResult
    static func toggle(_ source: MetricSource, dayKey: String) -> Bool {
        let marked = !isMarked(source, dayKey: dayKey)
        set(source, marked: marked, dayKey: dayKey)
        return marked
    }

    /// 清空某一天的全部标记（用于「重置当天」入口）。
    /// - Parameter dayKey: 日期键。
    static func clear(dayKey: String) {
        var all = readAll()
        all.removeValue(forKey: dayKey)
        writeAll(all)
    }

    /// 读取整张标记表；解析失败时退回空表，避免损坏的持久化数据影响评分。
    private static func readAll() -> [String: [Int]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { return [:] }
        return raw
    }

    /// 写入整张标记表。
    private static func writeAll(_ value: [String: [Int]]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

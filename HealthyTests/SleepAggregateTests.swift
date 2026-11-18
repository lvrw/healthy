import Foundation
import Testing

struct SleepAggregateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func stages(_ intervals: [(start: Date, end: Date, stage: SleepStageKind)]) -> [SleepStageInterval] {
        intervals.map { SleepStageInterval(start: $0.start, end: $0.end, stage: $0.stage) }
    }

    /// 主睡眠中点应忽略午睡：夜睡 23:00→07:00（次日）含一段 14:00→15:00 午睡，
    /// 中点必须落在夜睡区间内（≈03:00），而不是被午睡拉到 07:00 之后。
    @Test func midpointIgnoresNap() {
        let nightStart = date(2026, 11, 3, 23, 0)
        let nightEnd = date(2026, 11, 4, 7, 0)
        let napStart = date(2026, 11, 4, 14, 0)
        let napEnd = date(2026, 11, 4, 15, 0)
        let data = stages([
            (nightStart, nightEnd, .core),
            (napStart, napEnd, .core),
        ])

        guard let span = mainSleepSpan(from: data) else {
            Issue.record("主睡眠区间不应为空")
            return
        }
        #expect(span.start == nightStart, "入睡点应为夜睡开始，而非午睡")
        #expect(span.end == nightEnd, "醒来点应为夜睡结束，而非午睡")

        let midpoint = span.start.addingTimeInterval(span.end.timeIntervalSince(span.start) / 2)
        // 以夜睡结束日（11-04）为日基准：03:00 = 180 分钟
        let dayBase = calendar.startOfDay(for: nightEnd)
        let midpointMinutes = midpoint.timeIntervalSince(dayBase) / 60
        #expect(abs(midpointMinutes - 180) < 1, "中点应≈180分钟(03:00)，实际\(midpointMinutes)")
    }

    /// 夜睡内部有 45 分钟清醒断层（03:00→03:45）应被合并为同一段主睡眠。
    @Test func intraNightAwakeningMerged() {
        let block1Start = date(2026, 11, 3, 22, 0)
        let block1End = date(2026, 11, 4, 3, 0)
        let block2Start = date(2026, 11, 4, 3, 45)
        let block2End = date(2026, 11, 4, 6, 0)
        let data = stages([
            (block1Start, block1End, .core),
            (block2Start, block2End, .rem),
        ])

        guard let span = mainSleepSpan(from: data) else {
            Issue.record("主睡眠区间不应为空")
            return
        }
        #expect(span.start == block1Start)
        #expect(span.end == block2End)
    }

    /// 仅有一段睡眠时（无午睡）主睡眠区间就是它本身。
    @Test func singleSleepBlock() {
        let start = date(2026, 11, 3, 23, 30)
        let end = date(2026, 11, 4, 7, 30)
        let data = stages([(start, end, .deep)])
        guard let span = mainSleepSpan(from: data) else {
            Issue.record("主睡眠区间不应为空")
            return
        }
        #expect(span.start == start && span.end == end)
    }

    /// 没有任何睡眠片段时返回 nil，避免后续写出错误的中点。
    @Test func noSleepReturnsNil() {
        #expect(mainSleepSpan(from: []) == nil)
    }
}

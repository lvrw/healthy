import Foundation

enum Baseline {
    static func compute(
        history: [DailySnapshot],
        today: DailySnapshot,
        config: ScoringConfig = ScoringConfig(),
        calendar: Calendar = .current
    ) -> BaselineResult {
        let todayStart = calendar.startOfDay(for: today.date)
        let windowStart = DayKey.addingDays(-config.baselineWindowDays, to: todayStart, calendar: calendar)
        let rows = history.filter { snapshot in
            let start = calendar.startOfDay(for: snapshot.date)
            return start >= windowStart && start < todayStart
        }

        let hrvValues = rows.compactMap { MetricSanitizer.value($0.hrvSDNN, in: MetricRange.hrv) }
        let restingHRValues = rows.compactMap { MetricSanitizer.value($0.restingHR, in: MetricRange.restingHR) }

        let hrvLog = stats(
            values: hrvValues.map { log($0 + 1) },
            floor: config.hrvLogSDFloor,
            minCount: config.minBaselineDays
        )
        let restingHR = stats(
            values: restingHRValues,
            floor: config.restingHRSDFloor,
            minCount: config.minBaselineDays
        )
        let averageHR = stats(
            values: rows.compactMap { MetricSanitizer.value($0.avgHR, in: MetricRange.heartRate) },
            floor: config.avgHRSDFloor,
            minCount: config.minBaselineDays
        )
        let wristTemp = stats(
            values: rows.compactMap { MetricSanitizer.value($0.wristTempC, in: MetricRange.wristTemp) },
            floor: config.tempSDFloor,
            minCount: config.minBaselineDays
        )
        let respiratory = stats(
            values: rows.compactMap { MetricSanitizer.value($0.respiratoryRate, in: MetricRange.respiratoryRate) },
            floor: config.respSDFloor,
            minCount: config.minBaselineDays
        )
        let spo2 = stats(
            values: rows.compactMap { MetricSanitizer.value($0.spo2, in: MetricRange.spo2) },
            floor: config.spo2SDFloor,
            minCount: config.minBaselineDays
        )

        let vo2Max = stats(
            values: rows.compactMap { MetricSanitizer.value($0.vo2Max, in: MetricRange.vo2Max) },
            floor: config.vo2MaxSDFloor,
            minCount: config.minSparseBaselineDays
        )
        let walkingSpeed = stats(
            values: rows.compactMap { MetricSanitizer.value($0.walkingSpeedMps, in: MetricRange.walkingSpeed) },
            floor: config.walkingSpeedSDFloor,
            minCount: config.minSparseBaselineDays
        )
        let walkingSteadiness = stats(
            values: rows.compactMap { MetricSanitizer.value($0.walkingSteadinessPct, in: MetricRange.walkingSteadinessPct) },
            floor: config.walkingSteadinessSDFloor,
            minCount: config.minSparseBaselineDays
        )
        let systolicBP = stats(
            values: rows.compactMap { MetricSanitizer.value($0.systolicBP, in: MetricRange.systolicBP) },
            floor: config.systolicBPSDFloor,
            minCount: config.minSparseBaselineDays
        )
        let diastolicBP = stats(
            values: rows.compactMap { MetricSanitizer.value($0.diastolicBP, in: MetricRange.diastolicBP) },
            floor: config.diastolicBPSDFloor,
            minCount: config.minSparseBaselineDays
        )
        let basalBodyTemp = stats(
            values: rows.compactMap { MetricSanitizer.value($0.basalBodyTempC, in: MetricRange.basalBodyTemp) },
            floor: config.basalTempSDFloor,
            minCount: config.minSparseBaselineDays
        )
        let bloodGlucose = stats(
            values: rows.compactMap { MetricSanitizer.value($0.bloodGlucoseMgDl, in: MetricRange.bloodGlucose) },
            floor: config.bloodGlucoseSDFloor,
            minCount: config.minSparseBaselineDays
        )

        return BaselineResult(
            hrvLog: hrvLog,
            restingHR: restingHR,
            averageHeartRate: averageHR,
            wristTempC: wristTemp,
            respiratoryRate: respiratory,
            spo2: spo2,
            vo2Max: vo2Max,
            walkingSpeed: walkingSpeed,
            walkingSteadiness: walkingSteadiness,
            systolicBP: systolicBP,
            diastolicBP: diastolicBP,
            basalBodyTemp: basalBodyTemp,
            bloodGlucose: bloodGlucose,
            baselineDays: max(hrvValues.count, restingHRValues.count)
        )
    }

    static func stats(values: [Double], floor: Double, minCount: Int) -> BaselineStats? {
        guard values.count >= minCount else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, values.count - 1))
        return BaselineStats(mean: mean, sd: max(sqrt(variance), floor), count: values.count)
    }
}

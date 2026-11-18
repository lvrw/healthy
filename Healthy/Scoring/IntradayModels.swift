import Foundation

struct HRVSamplePoint: Sendable, Equatable, Identifiable {
    var id: Date { date }
    var date: Date
    var sdnn: Double?
    var rmssd: Double?
}

struct HeartRateBucket: Sendable, Equatable, Identifiable {
    var id: Date { start }
    var start: Date
    var minutes: Int
    var average: Double

    var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
}

struct WorkoutInterval: Sendable, Equatable {
    var start: Date
    var end: Date
}

struct IntradaySignals: Sendable, Equatable {
    var hrvPoints: [HRVSamplePoint]
    var heartRateBuckets: [HeartRateBucket]
    var workouts: [WorkoutInterval]

    static let empty = IntradaySignals(hrvPoints: [], heartRateBuckets: [], workouts: [])
}

import Foundation
import Testing

struct UserProfileTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 9)) ?? .now
    }

    private func testDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "UserProfileTests-\(UUID().uuidString)")!
        return suite
    }

    @Test func chronologicalAgeUsesDayCount() {
        let profile = UserProfile(
            birthDate: calendar.date(from: DateComponents(year: 1990, month: 5, day: 15)),
            isMale: true
        )
        let age = profile.chronologicalAge(now: now, calendar: calendar)
        #expect(age != nil)
        #expect(36.4 < age!)
        #expect(age! < 36.6)
    }

    @Test func missingBirthDateYieldsNilAge() {
        let profile = UserProfile(birthDate: nil, isMale: nil)
        #expect(profile.chronologicalAge(now: now, calendar: calendar) == nil)
    }

    @Test func roundTripThroughUserDefaults() throws {
        let defaults = testDefaults()
        let birth = try #require(calendar.date(from: DateComponents(year: 1988, month: 3, day: 2)))
        UserProfile(birthDate: birth, isMale: false).save(defaults: defaults)
        let loaded = UserProfile.load(defaults: defaults)
        #expect(loaded.isMale == false)
        #expect(loaded.birthDate == birth)
    }

    @Test func manualEntryOverridesHealthKitProfile() {
        // 本机手动填写优先：同步了健康档案后，用户在设置里修改仍应生效。
        let profile = UserProfile(
            birthDate: calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)),
            isMale: false
        )
        let effective = profile.effective(
            healthKitAge: 40,
            healthKitMale: true,
            now: now,
            calendar: calendar
        )
        // 1990-01-01 → 2026-11-09 ≈ 36.85 岁
        #expect(36.7 < effective.chronologicalAge!)
        #expect(effective.chronologicalAge! < 37.0)
        #expect(effective.isMale == false)
    }

    @Test func healthKitValuesAreUsedWhenLocalIsEmpty() {
        // 用户没编辑过：直接用健康 App 档案值；两边都没有则留空。
        let profile = UserProfile(birthDate: nil, isMale: nil)
        let effective = profile.effective(
            healthKitAge: 36.5,
            healthKitMale: true,
            now: now,
            calendar: calendar
        )
        #expect(effective.chronologicalAge == 36.5)
        #expect(effective.isMale == true)

        let empty = profile.effective(
            healthKitAge: nil,
            healthKitMale: nil,
            now: now,
            calendar: calendar
        )
        #expect(empty.chronologicalAge == nil)
        #expect(empty.isMale == nil)
    }

    @Test func localValuesFillMissingHealthKitProfile() {
        let profile = UserProfile(
            birthDate: calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)),
            isMale: true
        )
        let effective = profile.effective(
            healthKitAge: nil,
            healthKitMale: nil,
            now: now,
            calendar: calendar
        )
        #expect(effective.isMale == true)
        // 1990-01-01 → 2026-11-09 ≈ 36.85 岁
        #expect(36.7 < effective.chronologicalAge!)
        #expect(effective.chronologicalAge! < 37.0)
    }
}

// configured by qoder

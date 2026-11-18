import Foundation

struct UserProfile: Sendable, Equatable {
    var birthDate: Date?
    var isMale: Bool?

    static func load(defaults: UserDefaults = .standard) -> UserProfile {
        let birth = defaults.object(forKey: birthKey) as? TimeInterval
        let sex = defaults.string(forKey: sexKey)
        return UserProfile(
            birthDate: birth.map { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil } ?? nil,
            isMale: sex == "male" ? true : (sex == "female" ? false : nil)
        )
    }

    func save(defaults: UserDefaults = .standard) {
        if let birthDate {
            defaults.set(birthDate.timeIntervalSince1970, forKey: Self.birthKey)
        } else {
            defaults.removeObject(forKey: Self.birthKey)
        }
        switch isMale {
        case .some(true): defaults.set("male", forKey: Self.sexKey)
        case .some(false): defaults.set("female", forKey: Self.sexKey)
        case nil: defaults.removeObject(forKey: Self.sexKey)
        }
    }

    func chronologicalAge(now: Date = .now, calendar: Calendar = .current) -> Double? {
        guard let birthDate else { return nil }
        let days = calendar.dateComponents([.day], from: birthDate, to: now).day ?? 0
        guard days > 0 else { return nil }
        return Double(days) / 365.25
    }

    /// 生效规则：本机「设置 → 基本资料」手动填写的资料优先生效
    /// （用户即使同步了健康档案也可以修改覆盖），缺失时用健康档案兜底。
    func effective(
        healthKitAge: Double?,
        healthKitMale: Bool?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> EffectiveProfile {
        EffectiveProfile(
            chronologicalAge: chronologicalAge(now: now, calendar: calendar) ?? healthKitAge,
            isMale: isMale ?? healthKitMale
        )
    }

    private static let birthKey = "healthy.profile.birthDate"
    private static let sexKey = "healthy.profile.sex"
}

struct EffectiveProfile: Sendable, Equatable {
    var chronologicalAge: Double?
    var isMale: Bool?
}

// configured by qoder

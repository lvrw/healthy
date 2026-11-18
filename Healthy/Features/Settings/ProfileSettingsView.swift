import SwiftUI

/// 基本资料：只展示「出生日期」和「性别」两项，不再分健康档案 / 本机两份。
/// 显示值 = 用户在本页的编辑值（优先） ?? 健康 App 档案同步值；两者都没有就留空。
/// 用户一旦修改即写入本机，之后始终以修改值为准。
struct ProfileSettingsView: View {
    @State private var birthDate: Date = Calendar.current.date(
        byAdding: .year, value: -30, to: .now
    ) ?? .now
    @State private var hasBirthDate = false
    @State private var sexSelection = "unset"
    @State private var hkBirthDate: Date?
    @State private var hkIsMale: Bool?
    @State private var hkNotice: String?

    var body: some View {
        Form {
            Section {
                if hasBirthDate {
                    DatePicker(
                        "出生日期",
                        selection: Binding(
                            get: { birthDate },
                            set: { updateBirthDate($0) }
                        ),
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                } else {
                    HStack {
                        Text("出生日期")
                        Spacer()
                        Text("未获取")
                            .foregroundStyle(.tertiary)
                    }
                    Button("设置出生日期") {
                        updateBirthDate(birthDate)
                    }
                    .font(.subheadline)
                }
                Picker("性别", selection: Binding(
                    get: { sexSelection },
                    set: { updateSex($0) }
                )) {
                    Text("未设置").tag("unset")
                    Text("男").tag("male")
                    Text("女").tag("female")
                }
            } header: {
                Text("基本资料")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("默认从健康 App 健康档案同步，读取不到则留空；在这里修改后以你的填写为准，仅存本机。")
                    if hkNotice != nil {
                        Text("健康 App 档案未读取到，可到「设置 → 健康数据」检查授权。")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("基本资料")
        .onAppear {
            resolve()
        }
        .task {
            await loadHealthKitCharacteristics()
        }
    }

    /// 合并两个来源：本机编辑值优先，健康档案兜底，都为空则显示空态。
    /// 直接改 @State，不经过 Picker / DatePicker 的 Binding setter，
    /// 避免「同步过来的值」被误当成用户编辑写回本机。
    private func resolve() {
        let local = UserProfile.load()
        if let localDate = local.birthDate {
            birthDate = localDate
            hasBirthDate = true
        } else if let hkBirthDate {
            birthDate = hkBirthDate
            hasBirthDate = true
        } else {
            hasBirthDate = false
        }

        if let localMale = local.isMale {
            sexSelection = localMale ? "male" : "female"
        } else if let hkIsMale {
            sexSelection = hkIsMale ? "male" : "female"
        } else {
            sexSelection = "unset"
        }
    }

    private func loadHealthKitCharacteristics() async {
        let service = HealthKitService()
        // 出生日期/性别需先向 HealthKit 声明读取，否则 dateOfBirthComponents() 抛 notDetermined。
        await service.ensureCharacteristicAuthorization()
        let characteristics = await service.fetchCharacteristics()
        // 用健康档案里的真实出生日期；此前用「年龄取整反推」会偏差到半年。
        hkBirthDate = characteristics.birthDate
        hkIsMale = characteristics.isMale
        hkNotice = characteristics.notice
        resolve()
    }

    private func updateBirthDate(_ date: Date) {
        birthDate = date
        hasBirthDate = true
        let local = UserProfile.load()
        UserProfile(
            birthDate: Calendar.current.startOfDay(for: date),
            isMale: local.isMale
        ).save()
    }

    private func updateSex(_ selection: String) {
        guard selection != sexSelection else { return }
        sexSelection = selection
        let local = UserProfile.load()
        let isMale: Bool? = switch selection {
        case "male": true
        case "female": false
        default: nil
        }
        UserProfile(birthDate: local.birthDate, isMale: isMale).save()
        // 选「未设置」= 清除本机覆盖，立即回落到健康档案（没有则保持空态）。
        if selection == "unset" {
            resolve()
        }
    }
}

#Preview {
    NavigationStack {
        ProfileSettingsView()
    }
}

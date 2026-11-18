import Foundation
import HealthKit
import Testing

struct HealthKitAuthorizationTests {
    /// 出生日期/性别必须在 read 集合里声明，否则读取时抛 errorAuthorizationNotDetermined。
    @Test func readTypesIncludeCharacteristicTypes() {
        let types = HealthKitTypes.readTypes
        #expect(types.contains(HealthKitTypes.dateOfBirth))
        #expect(types.contains(HealthKitTypes.biologicalSex))
        #expect(HealthKitTypes.characteristicTypes.count == 2)
    }

    @Test func authorizationNotDeterminedIsRecognized() {
        let notDetermined = NSError(
            domain: HKErrorDomain,
            code: HKError.errorAuthorizationNotDetermined.rawValue,
            userInfo: nil
        )
        #expect(HealthKitTypes.isAuthorizationNotDetermined(notDetermined))

        let noData = NSError(domain: HKErrorDomain, code: HKError.errorNoData.rawValue, userInfo: nil)
        #expect(!HealthKitTypes.isAuthorizationNotDetermined(noData))

        let denied = NSError(domain: HKErrorDomain, code: HKError.errorAuthorizationDenied.rawValue, userInfo: nil)
        #expect(!HealthKitTypes.isAuthorizationNotDetermined(denied))

        let other = NSError(domain: NSCocoaErrorDomain, code: 1, userInfo: nil)
        #expect(!HealthKitTypes.isAuthorizationNotDetermined(other))
    }
}

import XCTest
import Security
@testable import ClipBridgeKit

final class PairingStoreTests: XCTestCase {
    private let info = PairingInfo(host: "192.168.1.10", port: 8765, token: "tok")

    func testEmptyStoreIsNotPaired() {
        XCTAssertEqual(SharedPairingStore.inMemory().load(), .notPaired)
    }

    func testSaveThenLoadIsPaired() throws {
        let store = SharedPairingStore.inMemory()
        try store.save(info)
        XCTAssertEqual(store.load(), .paired(info))
    }

    func testInMemoryFactoryPreloadsPairing() {
        XCTAssertEqual(SharedPairingStore.inMemory(info).load(), .paired(info))
    }

    func testClearRemovesEverything() throws {
        let store = SharedPairingStore.inMemory(info)
        try store.clear()
        XCTAssertEqual(store.load(), .notPaired)
    }

    func testEndpointWithoutTokenReportsItemNotFound() {
        let store = SharedPairingStore(endpoints: InMemoryEndpointStore(endpoint: info.endpoint), tokens: InMemoryTokenStore())
        XCTAssertEqual(store.load(), .tokenUnavailable(endpoint: info.endpoint, reason: .itemNotFound))
    }

    func testTokenWithoutEndpointIsNotPaired() {
        let store = SharedPairingStore(endpoints: InMemoryEndpointStore(), tokens: InMemoryTokenStore(token: "tok"))
        XCTAssertEqual(store.load(), .notPaired)
    }

    func testKeychainFailureBecomesTokenUnavailableWithReason() {
        let tokens = InMemoryTokenStore(token: "tok", failure: .notAvailable)
        let store = SharedPairingStore(endpoints: InMemoryEndpointStore(endpoint: info.endpoint), tokens: tokens)
        XCTAssertEqual(store.load(), .tokenUnavailable(endpoint: info.endpoint, reason: .notAvailable))

        tokens.setFailure(.interactionNotAllowed)
        XCTAssertEqual(store.load(), .tokenUnavailable(endpoint: info.endpoint, reason: .interactionNotAllowed))

        tokens.setFailure(nil)
        XCTAssertEqual(store.load(), .paired(info))
    }

    func testKeychainFailureWithoutEndpointIsNotPaired() {
        let store = SharedPairingStore(endpoints: InMemoryEndpointStore(), tokens: InMemoryTokenStore(failure: .missingEntitlement))
        XCTAssertEqual(store.load(), .notPaired)
    }

    func testSaveLeavesEndpointUntouchedWhenKeychainFails() {
        let endpoints = InMemoryEndpointStore()
        let store = SharedPairingStore(endpoints: endpoints, tokens: InMemoryTokenStore(failure: .missingEntitlement))
        XCTAssertThrowsError(try store.save(info)) { error in
            XCTAssertEqual(error as? KeychainError, .missingEntitlement)
        }
        XCTAssertNil(endpoints.loadEndpoint())
        XCTAssertEqual(store.load(), .notPaired)
    }

    func testUserDefaultsEndpointStoreRoundTrip() throws {
        let suite = "clipbridge.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserDefaultsEndpointStore(defaults: defaults)
        XCTAssertNil(store.loadEndpoint())
        XCTAssertNil(store.pairedAt)

        store.save(info.endpoint)
        XCTAssertEqual(store.loadEndpoint(), info.endpoint)
        XCTAssertNotNil(store.pairedAt)

        store.clearEndpoint()
        XCTAssertNil(store.loadEndpoint())
        XCTAssertNil(store.pairedAt)
    }

    func testUserDefaultsEndpointStoreIgnoresCorruptPort() throws {
        let suite = "clipbridge.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("pc.local", forKey: UserDefaultsEndpointStore.hostKey)
        defaults.set(0, forKey: UserDefaultsEndpointStore.portKey)
        XCTAssertNil(UserDefaultsEndpointStore(defaults: defaults).loadEndpoint())
    }

    func testKeychainErrorStatusMapping() {
        XCTAssertEqual(KeychainError(status: errSecItemNotFound), .itemNotFound)
        XCTAssertEqual(KeychainError(status: errSecInteractionNotAllowed), .interactionNotAllowed)
        XCTAssertEqual(KeychainError(status: errSecMissingEntitlement), .missingEntitlement)
        XCTAssertEqual(KeychainError(status: errSecNotAvailable), .notAvailable)
        XCTAssertEqual(KeychainError(status: errSecDuplicateItem), .duplicateItem)
        XCTAssertEqual(KeychainError(status: -50), .status(-50))
        XCTAssertEqual(KeychainError.missingEntitlement.status, -34018)
        XCTAssertEqual(KeychainError.notAvailable.status, -25291)
        XCTAssertNil(KeychainError.unexpectedData.status)
    }

    func testKeychainAccessGroupNeedsExpandedPrefix() {
        XCTAssertEqual(KeychainAccessGroup.shared(appIdentifierPrefix: "L24ST657GM."), "L24ST657GM.com.charleschen.clipbridge.shared")
        XCTAssertEqual(KeychainAccessGroup.shared(appIdentifierPrefix: "L24ST657GM"), "L24ST657GM.com.charleschen.clipbridge.shared")
        XCTAssertEqual(KeychainAccessGroup.shared(appIdentifierPrefix: " L24ST657GM. "), "L24ST657GM.com.charleschen.clipbridge.shared")
        XCTAssertNil(KeychainAccessGroup.shared(appIdentifierPrefix: nil))
        XCTAssertNil(KeychainAccessGroup.shared(appIdentifierPrefix: ""))
        // Info.plist 没被构建系统展开时的原样值
        XCTAssertNil(KeychainAccessGroup.shared(appIdentifierPrefix: "$(AppIdentifierPrefix)"))
    }

    func testLiveStoreIsNilWithoutAppIdentifierPrefix() {
        // 测试进程的 Bundle.main 没有 AppIdentifierPrefix，live() 必须明确返回 nil 而不是静默降级
        XCTAssertNil(SharedPairingStore.live(bundle: .main))
    }
}

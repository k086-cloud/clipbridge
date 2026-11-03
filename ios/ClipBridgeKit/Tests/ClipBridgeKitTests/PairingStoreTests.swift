import XCTest
import Security
@testable import ClipBridgeKit

final class PairingStoreTests: XCTestCase {
    private let info = PairingInfo(host: "192.168.1.10", port: 8765, token: "tok")

    /// 独立的 UserDefaults suite，并在用完后删掉 ~/Library/Preferences 里的 plist（removePersistentDomain 只清内容不删文件）。
    private func makeDefaults() throws -> UserDefaults {
        let suite = "clipbridge.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            let plist = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences/\(suite).plist")
            try? FileManager.default.removeItem(at: plist)
        }
        return defaults
    }

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

    func testClearRemovesEndpointAndToken() throws {
        let endpoints = InMemoryEndpointStore(endpoint: info.endpoint)
        let tokens = InMemoryTokenStore(token: "tok")
        let store = SharedPairingStore(endpoints: endpoints, tokens: tokens)
        try store.clear()
        XCTAssertEqual(store.load(), .notPaired)
        XCTAssertNil(endpoints.loadEndpoint())
        XCTAssertNil(try tokens.loadToken())
    }

    func testClearLeavesEndpointUntouchedWhenKeychainFails() {
        // 和 save 对称：Keychain 删不掉就不动地址，UI 继续显示已配对，用户可以重试
        let endpoints = InMemoryEndpointStore(endpoint: info.endpoint)
        let tokens = InMemoryTokenStore(token: "tok", failure: .notAvailable)
        let store = SharedPairingStore(endpoints: endpoints, tokens: tokens)
        XCTAssertThrowsError(try store.clear()) { error in
            XCTAssertEqual(error as? KeychainError, .notAvailable)
        }
        XCTAssertEqual(endpoints.loadEndpoint(), info.endpoint)
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
        let store = UserDefaultsEndpointStore(defaults: try makeDefaults())
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
        let defaults = try makeDefaults()
        defaults.set("pc.local", forKey: UserDefaultsEndpointStore.hostKey)
        defaults.set(0, forKey: UserDefaultsEndpointStore.portKey)
        XCTAssertNil(UserDefaultsEndpointStore(defaults: defaults).loadEndpoint())
        defaults.set(70000, forKey: UserDefaultsEndpointStore.portKey)
        XCTAssertNil(UserDefaultsEndpointStore(defaults: defaults).loadEndpoint())
    }

    func testUserDefaultsEndpointStoreIgnoresCorruptHost() throws {
        for bad in ["evil.com/path", "192.168.1. 5", " 192.168.1.5", "user@pc", "[fe80::1]", ""] {
            let defaults = try makeDefaults()
            defaults.set(bad, forKey: UserDefaultsEndpointStore.hostKey)
            defaults.set(8765, forKey: UserDefaultsEndpointStore.portKey)
            XCTAssertNil(UserDefaultsEndpointStore(defaults: defaults).loadEndpoint(), "host: \(bad)")
        }
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

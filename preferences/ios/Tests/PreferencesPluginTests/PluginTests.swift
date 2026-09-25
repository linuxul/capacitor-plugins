import XCTest
import Capacitor
@testable import PreferencesPlugin

class PreferencesTests: XCTestCase {
    // A group of its own, so the test neither reads nor clears the defaults of anything else.
    private let group = "CapacitorPreferencesTests"

    override func tearDown() {
        Preferences(with: PreferencesConfiguration(for: .named(group))).removeAll()
        super.tearDown()
    }

    func testMethodsWithoutAKeyAreRejected() {
        let plugin = PreferencesPlugin()
        let methods: [(String, (CAPPluginCall) throws -> Void)] = [
            ("get", plugin.get),
            ("set", plugin.set),
            ("remove", plugin.remove)
        ]
        for (name, method) in methods {
            XCTAssertThrowsError(try method(call(name, [:])), name) { error in
                // The bridge rejects the call with this error.
                XCTAssertEqual((error as? CAPPluginError)?.message, "Must provide a key", name)
                XCTAssertNil((error as? CAPPluginError)?.code, name)
            }
        }
    }

    func testSetGetAndRemoveAValue() throws {
        let plugin = PreferencesPlugin()
        _ = try settle(plugin.configure, "configure", ["group": group])

        _ = try settle(plugin.set, "set", ["key": "name", "value": "Capacitor"])
        XCTAssertEqual(try settle(plugin.get, "get", ["key": "name"])?["value"] as? String, "Capacitor")
        XCTAssertEqual(try settle(plugin.keys, "keys", [:])?["keys"] as? [String], ["name"])

        _ = try settle(plugin.remove, "remove", ["key": "name"])
        // A missing value is resolved as nil, which the bridge sends as null.
        let removed = try XCTUnwrap(try settle(plugin.get, "get", ["key": "name"]))
        XCTAssertTrue(removed.keys.contains("value"))
        XCTAssertNil(removed["value"] as? String)
    }

    /// Calls a synchronous method, which settles its call before returning, and returns what it resolved with.
    private func settle(_ method: (CAPPluginCall) throws -> Void, _ name: String, _ options: JSObject) throws -> PluginCallResultData? {
        var resolved = false
        var data: PluginCallResultData?
        try method(CAPPluginCall(callbackId: "test", methodName: name, options: options, success: { result, _ in
            resolved = true
            data = result.data
        }, error: { error in
            XCTFail("\(name) rejected: \(error.message)")
        }))
        XCTAssertTrue(resolved, "\(name) must resolve before returning")
        return data
    }

    private func call(_ method: String, _ options: JSObject) -> CAPPluginCall {
        return CAPPluginCall(callbackId: "test", methodName: method, options: options, success: { _, _ in
            XCTFail("\(method) must not resolve")
        }, error: { _ in
            XCTFail("\(method) answers by throwing")
        })
    }
}

import XCTest
import Network
import Capacitor
@testable import CAPNetworkPlugin

class NetworkTests: XCTestCase {
    // The monitor reports from its own queue and the observer runs on the main queue; allow for a loaded machine.
    private let timeout: TimeInterval = 20

    func testAnUnsatisfiedPathIsNotConnected() {
        for (usesWiFi, usesCellular) in [(false, false), (true, false), (false, true), (true, true)] {
            XCTAssertEqual(CAPNetworkPlugin.Network.connection(status: .unsatisfied, usesWiFi: usesWiFi, usesCellular: usesCellular), .unavailable)
        }
    }

    func testASatisfiedPathOverWiFiOrAnyOtherInterfaceIsWifi() {
        XCTAssertEqual(CAPNetworkPlugin.Network.connection(status: .satisfied, usesWiFi: true, usesCellular: false), .wifi)
        // Wired Ethernet, loopback and other interfaces: the reachability flags reported them as Wi-Fi.
        XCTAssertEqual(CAPNetworkPlugin.Network.connection(status: .satisfied, usesWiFi: false, usesCellular: false), .wifi)
    }

    func testASatisfiedPathOverCellularAloneIsCellular() {
        XCTAssertEqual(CAPNetworkPlugin.Network.connection(status: .satisfied, usesWiFi: false, usesCellular: true), .cellular)
        XCTAssertEqual(CAPNetworkPlugin.Network.connection(status: .satisfied, usesWiFi: true, usesCellular: true), .wifi)
    }

    func testAPathThatANewConnectionWouldBringUpIsConnected() {
        XCTAssertEqual(CAPNetworkPlugin.Network.connection(status: .requiresConnection, usesWiFi: false, usesCellular: true), .cellular)
        XCTAssertEqual(CAPNetworkPlugin.Network.connection(status: .requiresConnection, usesWiFi: false, usesCellular: false), .wifi)
    }

    func testJavaScriptValues() {
        XCTAssertEqual(CAPNetworkPlugin.Network.Connection.wifi.jsStringValue, "wifi")
        XCTAssertEqual(CAPNetworkPlugin.Network.Connection.cellular.jsStringValue, "cellular")
        XCTAssertEqual(CAPNetworkPlugin.Network.Connection.unavailable.jsStringValue, "none")
        XCTAssertTrue(CAPNetworkPlugin.Network.Connection.wifi.isConnected)
        XCTAssertTrue(CAPNetworkPlugin.Network.Connection.cellular.isConnected)
        XCTAssertFalse(CAPNetworkPlugin.Network.Connection.unavailable.isConnected)
    }

    func testTheObserverHearsTheFirstStatusAndGetStatusAgrees() throws {
        let implementation = try CAPNetworkPlugin.Network()
        let reported = expectation(description: "the monitor reports the current path")
        var observed: CAPNetworkPlugin.Network.Connection?
        implementation.statusObserver = { status in
            if observed == nil {
                observed = status
                reported.fulfill()
            }
        }
        wait(for: [reported], timeout: timeout)

        let answered = expectation(description: "currentStatus answers")
        implementation.currentStatus { status in
            XCTAssertEqual(status, observed)
            answered.fulfill()
        }
        wait(for: [answered], timeout: timeout)
        XCTAssertEqual(implementation.currentStatus(), observed)
    }

    func testGetStatusResolvesWithTheJavaScriptShape() {
        let plugin = NetworkPlugin()
        plugin.load()
        let settled = expectation(description: "getStatus settles")
        var result: PluginCallResultData?
        plugin.getStatus(CAPPluginCall(callbackId: "test", methodName: "getStatus", options: [:], success: { callResult, _ in
            result = callResult.data
            settled.fulfill()
        }, error: { _ in
            XCTFail("getStatus must not reject")
        }))
        wait(for: [settled], timeout: timeout)
        XCTAssertNotNil(result?["connected"] as? Bool)
        XCTAssertTrue(["wifi", "cellular", "none"].contains(result?["connectionType"] as? String ?? ""))
    }
}

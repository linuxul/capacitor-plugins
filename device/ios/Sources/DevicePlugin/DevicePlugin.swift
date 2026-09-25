import Foundation
import UIKit
import Capacitor

@objc(DevicePlugin)
public class DevicePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DevicePlugin"
    public let jsName = "Device"
    public let pluginMethods: [CAPPluginMethod] = [
        .async("getId", DevicePlugin.getId),
        .async("getInfo", DevicePlugin.getInfo),
        .async("getBatteryInfo", DevicePlugin.getBatteryInfo),
        .promise("getLanguageCode", DevicePlugin.getLanguageCode),
        .promise("getLanguageTag", DevicePlugin.getLanguageTag)
    ]
    private let implementation = Device()

    // UIDevice is UIKit state: getId, getInfo and getBatteryInfo run on the main actor, not the bridge queue. They
    // only read, so it does not matter that async methods do not keep the order of the calls.

    @MainActor
    func getId(_ call: CAPPluginCall) async throws -> JSObject {
        guard let uuid = UIDevice.current.identifierForVendor else {
            throw CAPPluginError("Id not available")
        }
        return [
            "identifier": uuid.uuidString
        ]
    }

    @MainActor
    func getInfo(_ call: CAPPluginCall) async -> JSObject {
        var isSimulator = false
        var modelName = ""
        #if targetEnvironment(simulator)
        isSimulator = true
        modelName = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        modelName = implementation.getModelName()
        #endif

        let memUsed = implementation.getMemoryUsage()
        let systemVersionNum = implementation.getSystemVersionInt() ?? 0

        return [
            // UInt64 is not a JSValue; NSNumber serializes to the same JSON number.
            "memUsed": NSNumber(value: memUsed),
            "name": UIDevice.current.name,
            "model": modelName,
            "operatingSystem": "ios",
            "osVersion": UIDevice.current.systemVersion,
            "iOSVersion": systemVersionNum,
            "platform": "ios",
            "manufacturer": "Apple",
            "isVirtual": isSimulator,
            "webViewVersion": UIDevice.current.systemVersion
        ]
    }

    @MainActor
    func getBatteryInfo(_ call: CAPPluginCall) async -> JSObject {
        UIDevice.current.isBatteryMonitoringEnabled = true
        defer {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }

        return [
            "batteryLevel": UIDevice.current.batteryLevel,
            "isCharging": UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        ]
    }

    func getLanguageCode(_ call: CAPPluginCall) {
        let code = implementation.getLanguageCode()
        call.resolve([
            "value": code
        ])
    }

    func getLanguageTag(_ call: CAPPluginCall) {
        let tag = implementation.getLanguageTag()
        call.resolve([
            "value": tag
        ])
    }

}

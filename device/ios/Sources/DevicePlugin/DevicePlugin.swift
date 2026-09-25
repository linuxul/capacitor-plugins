import Foundation
import UIKit
import Capacitor

@objc(DevicePlugin)
public class DevicePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DevicePlugin"
    public let jsName = "Device"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("getId", DevicePlugin.getId),
        .promise("getInfo", DevicePlugin.getInfo),
        .promise("getBatteryInfo", DevicePlugin.getBatteryInfo),
        .promise("getLanguageCode", DevicePlugin.getLanguageCode),
        .promise("getLanguageTag", DevicePlugin.getLanguageTag)
    ]
    private let implementation = Device()

    func getId(_ call: CAPPluginCall) {
        if let uuid = UIDevice.current.identifierForVendor {
            call.resolve([
                "identifier": uuid.uuidString
            ])
        } else {
            call.reject("Id not available")
        }
    }
    func getInfo(_ call: CAPPluginCall) {
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

        call.resolve([
            "memUsed": memUsed,
            "name": UIDevice.current.name,
            "model": modelName,
            "operatingSystem": "ios",
            "osVersion": UIDevice.current.systemVersion,
            "iOSVersion": systemVersionNum,
            "platform": "ios",
            "manufacturer": "Apple",
            "isVirtual": isSimulator,
            "webViewVersion": UIDevice.current.systemVersion
        ])
    }

    func getBatteryInfo(_ call: CAPPluginCall) {
        UIDevice.current.isBatteryMonitoringEnabled = true

        call.resolve([
            "batteryLevel": UIDevice.current.batteryLevel,
            "isCharging": UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        ])

        UIDevice.current.isBatteryMonitoringEnabled = false
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

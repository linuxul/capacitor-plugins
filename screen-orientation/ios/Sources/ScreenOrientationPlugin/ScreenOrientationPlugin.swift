import Foundation
import UIKit
import Capacitor

@objc(ScreenOrientationPlugin)
public class ScreenOrientationPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ScreenOrientationPlugin"
    public let jsName = "ScreenOrientation"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "orientation", returnType: .promise),
        CAPPluginMethod(name: "lock", returnType: .promise),
        CAPPluginMethod(name: "unlock", returnType: .promise)
    ]

    private let implementation = ScreenOrientation()

    override public func load() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil)
        if let viewController = (self.bridge?.viewController as? CAPBridgeViewController) {
            implementation.setCapacitorViewController(viewController)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc public func orientation(_ call: CAPPluginCall) {
        // UIDevice is UIKit state: read it on the main queue, not the bridge queue.
        let implementation = self.implementation
        DispatchQueue.main.async {
            call.resolve(["type": implementation.getCurrentOrientationType()])
        }
    }

    @objc public func lock(_ call: CAPPluginCall) {
        guard let lockToOrientation = call.getString("orientation") else {
            call.reject("Input option 'orientation' must be provided.")
            return
        }
        implementation.lock(lockToOrientation) { error in
            if let error = error {
                call.reject(error.localizedDescription)
            } else {
                call.resolve()
            }
        }
    }

    @objc public func unlock(_ call: CAPPluginCall) {
        implementation.unlock { error in
            if let error = error {
                call.reject(error.localizedDescription)
            } else {
                call.resolve()
            }
        }
    }

    @objc private func orientationDidChange() {
        // Ignore changes in orientation if unknown, face up, or face down
        if UIDevice.current.orientation.isValidInterfaceOrientation {
            let orientation = implementation.getCurrentOrientationType()
            notifyListeners("screenOrientationChange", data: ["type": orientation])
        }
    }
}

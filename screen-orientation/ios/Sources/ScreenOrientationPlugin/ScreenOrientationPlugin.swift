import Foundation
import UIKit
import Capacitor

@objc(ScreenOrientationPlugin)
public class ScreenOrientationPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ScreenOrientationPlugin"
    public let jsName = "ScreenOrientation"
    public let pluginMethods: [CAPPluginMethod] = [
        .async("orientation", ScreenOrientationPlugin.orientation),
        .promise("lock", ScreenOrientationPlugin.lock),
        .promise("unlock", ScreenOrientationPlugin.unlock)
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

    /// UIDevice is UIKit state: the method runs on the main actor, not the bridge queue.
    @MainActor
    public func orientation(_ call: CAPPluginCall) async -> JSObject {
        return ["type": implementation.getCurrentOrientationType()]
    }

    // lock and unlock stay synchronous: the bridge queue runs them in the order of the calls and the implementation
    // hands the UIKit work to the main queue in that order, so a lock after an unlock wins. Async methods would not
    // keep that order.

    public func lock(_ call: CAPPluginCall) throws {
        guard let lockToOrientation = call.getString("orientation") else {
            throw CAPPluginError("Input option 'orientation' must be provided.")
        }
        implementation.lock(lockToOrientation) { error in
            if let error = error {
                call.reject(error.localizedDescription)
            } else {
                call.resolve()
            }
        }
    }

    public func unlock(_ call: CAPPluginCall) {
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

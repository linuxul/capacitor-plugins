import Foundation
import UIKit
import Capacitor

public class ScreenOrientation: NSObject {

    enum ScreenOrientationError: Error {
        case noWindowScene
    }

    private var supportedOrientations: [Int] = []
    // Weak: the bridge view controller owns the bridge that owns the plugin holding this object. A strong reference
    // closed a cycle that kept the view controller, its web view and the bridge alive.
    private weak var capViewController: CAPBridgeViewController?

    public func setCapacitorViewController(_ viewController: CAPBridgeViewController) {
        self.capViewController = viewController
        self.supportedOrientations = viewController.supportedOrientations
    }

    /// The orientation of the device as a screen orientation type. Call on the main thread: UIDevice is UIKit state.
    public func getCurrentOrientationType() -> String {
        let currentOrientation: UIDeviceOrientation = UIDevice.current.orientation
        return fromDeviceOrientationToOrientationType(currentOrientation)
    }

    public func lock(_ orientationType: String, completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            let orientation = self.fromOrientationTypeToInt(orientationType)
            self.capViewController?.supportedOrientations = [orientation]
            let mask = self.fromOrientationTypeToMask(orientationType)
            self.requestGeometryUpdate(mask, completion: completion)
        }
    }

    public func unlock(completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            self.capViewController?.supportedOrientations = self.supportedOrientations
            self.requestGeometryUpdate(.all, completion: completion)
        }
    }

    /// Asks the window scene for `mask` and calls `completion` exactly once. UIKit calls the error handler of
    /// `requestGeometryUpdate` only when the request fails, and may call it after the request returns, so the call
    /// completes when the request has been made; an error reported before that wins, and a later one is logged. The
    /// completion used to run twice for a failed request: with the error and then with nil. Call on the main thread.
    private func requestGeometryUpdate(_ mask: UIInterfaceOrientationMask, completion: @escaping (Error?) -> Void) {
        guard let windowScene = windowScene() else {
            completion(ScreenOrientationError.noWindowScene)
            return
        }
        let once = CompletionOnce(completion)
        windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            if !once.complete(error) {
                CAPLog.print("⚡️ ScreenOrientation: the orientation request failed after the call settled: \(error.localizedDescription)")
            }
        }
        once.complete(nil)
    }

    /// The scene showing the Capacitor view controller, or the foreground scene when that view is not in a window.
    /// `connectedScenes.first` could be a background scene when the app has more than one. Call on the main thread.
    private func windowScene() -> UIWindowScene? {
        if let scene = capViewController?.viewIfLoaded?.window?.windowScene {
            return scene
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return ScreenOrientation.preferredScene(scenes, activationState: { $0.activationState })
    }

    /// The first foreground-active scene, else the first foreground-inactive one (a scene that is launching or shows a
    /// system alert), else the first scene.
    static func preferredScene<Scene>(_ scenes: [Scene], activationState: (Scene) -> UIScene.ActivationState) -> Scene? {
        return scenes.first { activationState($0) == .foregroundActive }
            ?? scenes.first { activationState($0) == .foregroundInactive }
            ?? scenes.first
    }

    func fromDeviceOrientationToOrientationType(_ orientation: UIDeviceOrientation) -> String {
        switch orientation {
        case .landscapeLeft:
            return "landscape-primary"
        case .landscapeRight:
            return "landscape-secondary"
        case .portraitUpsideDown:
            return "portrait-secondary"
        default:
            // Case: portrait
            return "portrait-primary"
        }
    }

    func fromOrientationTypeToMask(_ orientationType: String) -> UIInterfaceOrientationMask {
        switch orientationType {
        case "any":
            return UIInterfaceOrientationMask.all
        case "landscape", "landscape-primary":
            // UIInterfaceOrientationMask.landscapeRight is the same as UIDeviceOrientation.landscapeLeft
            return UIInterfaceOrientationMask.landscapeRight
        case "landscape-secondary":
            // UIInterfaceOrientationMask.landscapeLeft is the same as UIDeviceOrientation.landscapeRight
            return UIInterfaceOrientationMask.landscapeLeft
        case "portrait-secondary":
            return UIInterfaceOrientationMask.portraitUpsideDown
        default:
            // Case: portrait-primary
            return UIInterfaceOrientationMask.portrait
        }
    }

    func fromOrientationTypeToInt(_ orientationType: String) -> Int {
        switch orientationType {
        case "any":
            return UIInterfaceOrientation.unknown.rawValue
        case "landscape", "landscape-primary":
            // UIInterfaceOrientation.landscapeRight is the same as UIDeviceOrientation.landscapeLeft
            // @see https://developer.apple.com/documentation/uikit/uiinterfaceorientation/landscaperight
            // @see https://developer.apple.com/documentation/uikit/uideviceorientation/landscapeleft
            return UIInterfaceOrientation.landscapeRight.rawValue
        case "landscape-secondary":
            // UIInterfaceOrientation.landscapeLeft is the same as UIDeviceOrientation.landscapeRight
            // @see https://developer.apple.com/documentation/uikit/uiinterfaceorientation/landscapeleft
            // @see https://developer.apple.com/documentation/uikit/uideviceorientation/landscaperight
            return UIInterfaceOrientation.landscapeLeft.rawValue
        case "portrait-secondary":
            return UIInterfaceOrientation.portraitUpsideDown.rawValue
        default:
            // Case: portrait-primary
            return UIInterfaceOrientation.portrait.rawValue
        }
    }

}

/// Calls a completion handler at most once, whichever thread gets there first.
final class CompletionOnce {
    private let lock = NSLock()
    private var handler: ((Error?) -> Void)?

    init(_ handler: @escaping (Error?) -> Void) {
        self.handler = handler
    }

    /// Calls the handler with `error` unless it has already been called. Returns false when it had been.
    @discardableResult
    func complete(_ error: Error?) -> Bool {
        let pending: ((Error?) -> Void)? = lock.withLock {
            defer { handler = nil }
            return handler
        }
        guard let pending else {
            return false
        }
        pending(error)
        return true
    }
}

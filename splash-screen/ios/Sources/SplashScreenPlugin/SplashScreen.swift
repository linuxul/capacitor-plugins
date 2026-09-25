import Foundation
import UIKit
import Capacitor

@objc public class SplashScreen: NSObject {

    var parentView: UIView
    var viewController = UIViewController()
    var spinner = UIActivityIndicatorView()
    var config: SplashScreenConfig = SplashScreenConfig()
    var hideTask: Any?
    var isVisible: Bool = false
    // Keeps the splash sized to the window while it is shown, when the parent view rotates or resizes. The observations
    // are invalidated when the splash is torn down; the string-based observers they replace were never removed.
    private var parentViewObservations: [NSKeyValueObservation] = []

    var isObservingParentView: Bool {
        return !parentViewObservations.isEmpty
    }

    init(parentView: UIView, config: SplashScreenConfig) {
        self.parentView = parentView
        self.config = config
    }

    public func showOnLaunch() {
        buildViews()
        if self.config.launchShowDuration == 0 {
            return
        }
        var settings = SplashScreenSettings()
        settings.showDuration = config.launchShowDuration
        settings.fadeInDuration = config.launchFadeInDuration
        settings.autoHide = config.launchAutoHide
        showSplash(settings: settings, completion: {}, isLaunchSplash: true)
    }

    public func show(settings: SplashScreenSettings, completion: @escaping () -> Void) {
        self.showSplash(settings: settings, completion: completion, isLaunchSplash: false)
    }

    public func hide(settings: SplashScreenSettings) {
        hideSplash(fadeOutDuration: settings.fadeOutDuration, isLaunchSplash: false)
    }

    private func showSplash(settings: SplashScreenSettings, completion: @escaping () -> Void, isLaunchSplash: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else {
                return
            }
            if let backgroundColor = strongSelf.config.backgroundColor {
                strongSelf.viewController.view.backgroundColor = backgroundColor
            }

            if strongSelf.config.showSpinner {
                if let style = strongSelf.config.spinnerStyle {
                    strongSelf.spinner.style = style
                }

                if let spinnerColor = strongSelf.config.spinnerColor {
                    strongSelf.spinner.color = spinnerColor
                }
            }

            strongSelf.observeParentView()
            strongSelf.parentView.addSubview(strongSelf.viewController.view)

            if strongSelf.config.showSpinner {
                strongSelf.parentView.addSubview(strongSelf.spinner)
                strongSelf.spinner.centerXAnchor.constraint(equalTo: strongSelf.parentView.centerXAnchor).isActive = true
                strongSelf.spinner.centerYAnchor.constraint(equalTo: strongSelf.parentView.centerYAnchor).isActive = true
            }

            strongSelf.parentView.isUserInteractionEnabled = false

            let fadeInDuration = TimeInterval(Double(settings.fadeInDuration) / 1000)
            UIView.transition(with: strongSelf.viewController.view, duration: fadeInDuration, options: .curveLinear, animations: {
                strongSelf.viewController.view.alpha = 1

                if strongSelf.config.showSpinner {
                    strongSelf.spinner.alpha = 1
                }
            }, completion: { (_: Bool) in
                strongSelf.isVisible = true

                if settings.autoHide {
                    strongSelf.hideTask = DispatchQueue.main.asyncAfter(
                        deadline: DispatchTime.now() + (Double(settings.showDuration) / 1000)
                    ) {
                        strongSelf.hideSplash(fadeOutDuration: settings.fadeOutDuration, isLaunchSplash: isLaunchSplash)
                        completion()
                    }
                } else {
                    completion()
                }
            })
        }
    }

    private func buildViews() {
        let storyboardName = Bundle.main.infoDictionary?["UILaunchStoryboardName"] as? String ?? "LaunchScreen"
        let storyboard = UIStoryboard(name: storyboardName.replacingOccurrences(of: ".storyboard", with: ""), bundle: nil)
        if let launchViewController = storyboard.instantiateInitialViewController() {
            viewController = launchViewController
        }

        updateSplashImageBounds()
        if config.showSpinner {
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.startAnimating()
        }
    }

    /// Starts resizing the splash with the parent view, which rotation resizes. Call on the main thread.
    private func observeParentView() {
        updateSplashImageBounds()
        guard parentViewObservations.isEmpty else {
            return
        }
        parentViewObservations = [
            parentView.observe(\.frame, options: [.new]) { [weak self] _, _ in
                self?.updateSplashImageBounds()
            },
            parentView.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                self?.updateSplashImageBounds()
            }
        ]
    }

    private func tearDown() {
        isVisible = false
        parentView.isUserInteractionEnabled = true
        viewController.view.removeFromSuperview()
        parentViewObservations.forEach { $0.invalidate() }
        parentViewObservations = []

        if config.showSpinner {
            spinner.removeFromSuperview()
        }
    }

    // Update the bounds for the splash image. This will also be called when
    // the parent view observers fire
    private func updateSplashImageBounds() {
        if let window = parentView.window ?? SplashScreen.foregroundWindow() {
            viewController.view.frame = CGRect(origin: CGPoint(x: 0, y: 0), size: window.bounds.size)
        } else {
            CAPLog.print("Unable to find root window object for SplashScreen bounds. Please file an issue")
        }
    }

    /// The window of the foreground scene, for when the splash is built before the web view is in a window.
    /// `UIApplication.delegate.window` is nil in apps with a scene delegate, and `connectedScenes.first` can be a
    /// background scene. Call on the main thread.
    private static func foregroundWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = preferredScene(scenes, activationState: { $0.activationState }) else {
            return nil
        }
        return scene.keyWindow ?? scene.windows.first
    }

    /// The first foreground-active scene, else the first foreground-inactive one (a scene that is still launching),
    /// else the first scene.
    static func preferredScene<Scene>(_ scenes: [Scene], activationState: (Scene) -> UIScene.ActivationState) -> Scene? {
        return scenes.first { activationState($0) == .foregroundActive }
            ?? scenes.first { activationState($0) == .foregroundInactive }
            ?? scenes.first
    }

    private func hideSplash(fadeOutDuration: Int, isLaunchSplash: Bool) {
        // isVisible changes on the main queue; hide is also called from the bridge queue.
        DispatchQueue.main.async {
            if isLaunchSplash, self.isVisible {
                CAPLog.print("SplashScreen.hideSplash: SplashScreen was automatically hidden after default timeout. " +
                                "You should call `SplashScreen.hide()` as soon as your web app is loaded (or increase the timeout). " +
                                "Read more at https://capacitorjs.com/docs/apis/splash-screen#hiding-the-splash-screen")
            }
            if !self.isVisible { return }
            let duration = TimeInterval(Double(fadeOutDuration) / 1000)
            UIView.transition(with: self.viewController.view, duration: duration, options: .curveLinear, animations: {
                self.viewController.view.alpha = 0

                if self.config.showSpinner {
                    self.spinner.alpha = 0
                }
            }, completion: { (_: Bool) in
                self.tearDown()
            })
        }
    }
}

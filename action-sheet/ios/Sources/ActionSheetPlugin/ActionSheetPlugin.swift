import Foundation
import UIKit
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(ActionSheetPlugin)
public class ActionSheetPlugin: CAPPlugin, CAPBridgedPlugin, UIAdaptivePresentationControllerDelegate {
    public let identifier = "ActionSheetPlugin"
    public let jsName = "ActionSheet"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("showActions", ActionSheetPlugin.showActions)
    ]
    private let implementation = ActionSheet()
    private var currentCall: CAPPluginCall?

    func showActions(_ call: CAPPluginCall) {
        let title = call.options["title"] as? String
        let message = call.options["message"] as? String
        let options = call.getArray("options", JSObject.self) ?? []

        // UIAlertAction and UIAlertController are UIKit objects: build them on the main queue, not the bridge queue.
        DispatchQueue.main.async { [weak self] in
            guard let self, let presenter = Self.topmostPresenter(from: self.bridge?.viewController) else {
                call.reject("Unable to display the action sheet: there is no view controller to present it from")
                return
            }
            var alertActions = [UIAlertAction]()
            var hasCancellableButton = false
            for (index, option) in options.enumerated() {
                let style = option["style"] as? String ?? "DEFAULT"
                let title = option["title"] as? String ?? ""
                var buttonStyle: UIAlertAction.Style = .default
                if style == "DESTRUCTIVE" {
                    buttonStyle = .destructive
                } else if style == "CANCEL" {
                    hasCancellableButton = true
                    buttonStyle = .cancel
                }
                let action = UIAlertAction(title: title, style: buttonStyle, handler: { [weak self] (_) in
                    call.resolve([
                        "index": index,
                        "canceled": buttonStyle == .cancel
                    ])
                    self?.currentCall = nil
                })
                alertActions.append(action)
            }

            let alertController = self.implementation.buildActionSheet(title: title, message: message, actions: alertActions)
            Self.centerPopover(alertController, on: presenter)
            presenter.present(alertController, animated: true) { [weak self] in
                if !hasCancellableButton {
                    self?.setupCancelationListeners(alertController, call)
                }
            }
        }
    }

    private func setupCancelationListeners(_ alertController: UIAlertController, _ call: CAPPluginCall) {
        let cancelable = call.getBool("cancelable", false)
        if #available(iOS 26, *) {
            self.currentCall = call
            alertController.presentationController?.delegate = self
        } else if cancelable {
            // For iOS versions below 26, setting the presentation controller delegate would result in a crash
            //  "Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'The presentation controller of an alert controller presenting as an alert must not have its delegate modified"
            //  Hence, the alternative by adding a gesture recognizer (which only works for iOS versions below 26)
            let gestureRecognizer = TapGestureRecognizerWithClosure {
                alertController.dismiss(animated: true, completion: nil)
                call.actionSheetCanceled()
            }
            let backgroundView = alertController.view.superview?.subviews.first
            backgroundView?.addGestureRecognizer(gestureRecognizer)
        }
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        self.currentCall?.actionSheetCanceled()
        self.currentCall = nil
    }
}

extension ActionSheetPlugin {
    /// The view controller to present from: the last controller in the chain presented over `root`, skipping one that
    /// is being dismissed. Presenting from `root` itself while it already presents a controller fails silently, which
    /// left the call pending when the app showed a modal over the web view. Call on the main thread.
    static func topmostPresenter(from root: UIViewController?) -> UIViewController? {
        var presenter = root
        while let presented = presenter?.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        return presenter
    }

    /// Centers the popover of `controller` (an action sheet on iPad) on the view of `presenter`, without an arrow.
    /// The anchor has to be in the presenter's hierarchy, which the bridge view controller's view is not when a
    /// full-screen modal covers it. Call on the main thread.
    static func centerPopover(_ controller: UIViewController, on presenter: UIViewController) {
        guard let popover = controller.popoverPresentationController, let view = presenter.view else {
            return
        }
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
}

// MARK: - TapGestureRecognizerWithClosure
private final class TapGestureRecognizerWithClosure: UITapGestureRecognizer {
    private let onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(target: nil, action: nil)
        self.addTarget(self, action: #selector(action))
    }

    @objc private func action() {
        onTap()
    }
}

private extension CAPPluginCall {
    func actionSheetCanceled() {
        resolve([
            "index": -1,
            "canceled": true
        ])
    }
}

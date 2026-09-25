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
        .async("showActions", ActionSheetPlugin.showActions)
    ]
    static let noPresenterMessage = "Unable to display the action sheet: there is no view controller to present it from"
    /// The answer of a sheet closed without choosing an option.
    static let canceled: JSObject = [
        "index": -1,
        "canceled": true
    ]
    private static var answerKey: UInt8 = 0

    private let implementation = ActionSheet()
    /// Cancels the sheet on screen when UIKit reports that it was dismissed. Set on iOS 26 for a sheet without a
    /// cancel option.
    private var cancelPresentedSheet: (() -> Void)?

    /// The sheet is UIKit: the method runs on the main actor and returns `{ index, canceled }` when the sheet closes.
    @MainActor
    func showActions(_ call: CAPPluginCall) async throws -> JSObject {
        let title = call.options["title"] as? String
        let message = call.options["message"] as? String
        let options = call.getArray("options", JSObject.self) ?? []
        let cancelable = call.getBool("cancelable", false)
        let hasCancellableButton = options.contains { ($0["style"] as? String) == "CANCEL" }

        guard let presenter = Self.topmostPresenter(from: bridge?.viewController) else {
            throw CAPPluginError(Self.noPresenterMessage)
        }
        var refused = false
        let choice = await withCheckedContinuation { (continuation: CheckedContinuation<JSObject, Never>) in
            let answer = OnceContinuation(continuation, fallback: Self.canceled)
            var alertActions = [UIAlertAction]()
            for (index, option) in options.enumerated() {
                let style = option["style"] as? String ?? "DEFAULT"
                let title = option["title"] as? String ?? ""
                var buttonStyle: UIAlertAction.Style = .default
                if style == "DESTRUCTIVE" {
                    buttonStyle = .destructive
                } else if style == "CANCEL" {
                    buttonStyle = .cancel
                }
                let action = UIAlertAction(title: title, style: buttonStyle, handler: { [weak self] (_) in
                    self?.cancelPresentedSheet = nil
                    answer.resume(returning: [
                        "index": index,
                        "canceled": buttonStyle == .cancel
                    ])
                })
                alertActions.append(action)
            }

            let alertController = implementation.buildActionSheet(title: title, message: message, actions: alertActions)
            Self.tie(answer, to: alertController)
            Self.centerPopover(alertController, on: presenter)
            presenter.present(alertController, animated: true) { [weak self, weak alertController, weak answer] in
                guard !hasCancellableButton, let self, let alertController, let answer else {
                    return
                }
                self.setupCancelationListeners(alertController, cancelable: cancelable) { [weak answer] in
                    answer?.resume(returning: Self.canceled)
                }
            }
            // UIKit sets presentedViewController as soon as it accepts a presentation.
            if presenter.presentedViewController !== alertController {
                refused = true
                answer.resume(returning: Self.canceled)
            }
        }
        if refused {
            throw CAPPluginError(Self.noPresenterMessage)
        }
        return choice
    }

    private func setupCancelationListeners(_ alertController: UIAlertController, cancelable: Bool, cancel: @escaping () -> Void) {
        if #available(iOS 26, *) {
            cancelPresentedSheet = cancel
            alertController.presentationController?.delegate = self
        } else if cancelable {
            // For iOS versions below 26, setting the presentation controller delegate would result in a crash
            //  "Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'The presentation controller of an alert controller presenting as an alert must not have its delegate modified"
            //  Hence, the alternative by adding a gesture recognizer (which only works for iOS versions below 26)
            let gestureRecognizer = TapGestureRecognizerWithClosure { [weak alertController] in
                alertController?.dismiss(animated: true, completion: nil)
                cancel()
            }
            let backgroundView = alertController.view.superview?.subviews.first
            backgroundView?.addGestureRecognizer(gestureRecognizer)
        }
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        let cancel = cancelPresentedSheet
        cancelPresentedSheet = nil
        cancel?()
    }
}

extension ActionSheetPlugin {
    /// Keeps `answer` alive exactly as long as `controller`. The option handlers and the cancelation listeners reach
    /// the answer while the sheet exists; once the sheet is released, however it went away (for example dismissed by
    /// the app without an option being chosen), an unanswered call gets the cancel answer instead of staying pending.
    static func tie(_ answer: AnyObject, to controller: UIViewController) {
        objc_setAssociatedObject(controller, &answerKey, answer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

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

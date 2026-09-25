import Foundation
import Capacitor
import UIKit

/**
 * Implement three common dialog types: alert, confirm, and prompt
 *
 * The dialogs are UIKit alerts: each method runs on the main actor and returns the answer when the alert closes.
 */
@objc(DialogPlugin)
public class DialogPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DialogPlugin"
    public let jsName = "Dialog"
    public let pluginMethods: [CAPPluginMethod] = [
        .async("alert", DialogPlugin.alert),
        .async("prompt", DialogPlugin.prompt),
        .async("confirm", DialogPlugin.confirm)
    ]
    static let noPresenterMessage = "Unable to display the dialog: there is no view controller to present it from"

    /// Resolves without data when the alert closes.
    @MainActor
    public func alert(_ call: CAPPluginCall) async throws {
        let title = call.options["title"] as? String
        guard let message = call.options["message"] as? String else {
            throw CAPPluginError("Please provide a message for the dialog")
        }
        let buttonTitle = call.options["buttonTitle"] as? String ?? "OK"

        try await Self.ask(over: bridge?.viewController, dismissed: ()) { answer in
            let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction(title: buttonTitle, style: UIAlertAction.Style.default, handler: { (_) in
                answer(())
            }))
            return alert
        }
    }

    /// Resolves with `{ value }`: true for the OK button, false for the cancel button or a dismissed alert.
    @MainActor
    public func confirm(_ call: CAPPluginCall) async throws -> JSObject {
        let title = call.options["title"] as? String
        guard let message = call.options["message"] as? String else {
            throw CAPPluginError("Please provide a message for the dialog")
        }
        let okButtonTitle = call.options["okButtonTitle"] as? String ?? "OK"
        let cancelButtonTitle = call.options["cancelButtonTitle"] as? String ?? "Cancel"
        let cancelled: JSObject = ["value": false]

        return try await Self.ask(over: bridge?.viewController, dismissed: cancelled) { answer in
            let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction(title: cancelButtonTitle, style: UIAlertAction.Style.default, handler: { (_) in
                answer(cancelled)
            }))
            alert.addAction(UIAlertAction(title: okButtonTitle, style: UIAlertAction.Style.default, handler: { (_) in
                answer(["value": true])
            }))
            return alert
        }
    }

    /// Resolves with `{ value, cancelled }`: the text for the OK button, an empty text and `cancelled: true` for the
    /// cancel button or a dismissed alert.
    @MainActor
    public func prompt(_ call: CAPPluginCall) async throws -> JSObject {
        let title = call.options["title"] as? String
        guard let message = call.options["message"] as? String else {
            throw CAPPluginError("Please provide a message for the dialog")
        }
        let okButtonTitle = call.options["okButtonTitle"] as? String ?? "OK"
        let cancelButtonTitle = call.options["cancelButtonTitle"] as? String ?? "Cancel"
        let inputPlaceholder = call.options["inputPlaceholder"] as? String ?? ""
        let inputText = call.options["inputText"] as? String ?? ""
        let cancelled: JSObject = ["value": "", "cancelled": true]

        return try await Self.ask(over: bridge?.viewController, dismissed: cancelled) { answer in
            let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)

            alert.addTextField { (textField) in
                textField.placeholder = inputPlaceholder
                textField.text = inputText
            }

            alert.addAction(UIAlertAction(title: cancelButtonTitle, style: UIAlertAction.Style.default, handler: { (_) in
                answer(cancelled)
            }))
            // Weak: the alert owns this action, and a strong reference would keep the alert alive after it closed.
            alert.addAction(UIAlertAction(title: okButtonTitle, style: UIAlertAction.Style.default, handler: { [weak alert] (_) in
                answer([
                    "value": alert?.textFields?.first?.text ?? "",
                    "cancelled": false
                ])
            }))
            return alert
        }
    }
}

extension DialogPlugin {
    /// Presents the alert that `makeAlert` builds from the topmost view controller over `root`, and returns the first
    /// answer its actions give through the function `makeAlert` receives.
    ///
    /// Every path answers once. Nothing to present from, or a presentation UIKit refuses (it logs and does nothing
    /// when the presenter is mid-transition or not in a window), throws; the call used to wait forever in the second
    /// case. An alert that goes away without an action, for example because the app dismissed the controllers over
    /// the web view, answers `dismissed` when it is released, since its actions can no longer answer.
    @MainActor
    static func ask<Answer>(over root: UIViewController?, dismissed: Answer,
                            _ makeAlert: (@escaping (Answer) -> Void) -> UIAlertController) async throws -> Answer {
        guard let presenter = topmostPresenter(from: root) else {
            throw CAPPluginError(noPresenterMessage)
        }
        var refused = false
        let answer = await withCheckedContinuation { (continuation: CheckedContinuation<Answer, Never>) in
            let once = OnceContinuation(continuation, fallback: dismissed)
            let alert = makeAlert { once.resume(returning: $0) }
            presenter.present(alert, animated: true, completion: nil)
            // UIKit sets presentedViewController as soon as it accepts a presentation.
            if presenter.presentedViewController !== alert {
                refused = true
                once.resume(returning: dismissed)
            }
        }
        if refused {
            throw CAPPluginError(noPresenterMessage)
        }
        return answer
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
}

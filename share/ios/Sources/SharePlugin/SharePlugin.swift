import Foundation
import Capacitor
import UIKit

@objc(SharePlugin)
public class SharePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SharePlugin"
    public let jsName = "Share"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("canShare", SharePlugin.canShare),
        .async("share", SharePlugin.share)
    ]

    static let noPresenterMessage = "Unable to display the share sheet: there is no view controller to present it from"

    /// How a share sheet closed.
    enum Outcome {
        case completed(activityType: String)
        case canceled
        case failed(Error)
    }

    func canShare(_ call: CAPPluginCall) {
        call.resolve([
            "value": true
        ])
    }

    /// The share sheet is UIKit: the method runs on the main actor and returns `{ activityType }` when the sheet closes
    /// after sharing. A sheet closed without sharing rejects with "Share canceled".
    @MainActor
    func share(_ call: CAPPluginCall) async throws -> JSObject {
        let items = SharePlugin.activityItems(from: call)
        if items.count == 0 {
            throw CAPPluginError("Must provide at least url, text or files")
        }
        let title = call.getString("title")

        let root = bridge?.viewController
        // A share is only in progress when a share sheet is already presented.
        if SharePlugin.isSharing(over: root) {
            throw CAPPluginError("Can't share while sharing is in progress")
        }
        // Present from the topmost presented view controller so the share sheet appears
        // above any view controller the app has presented over the webview. With nothing
        // presented this resolves to the bridge view controller, i.e. unchanged behaviour.
        guard let presenter = SharePlugin.topmostPresenter(from: root) else {
            throw CAPPluginError(SharePlugin.noPresenterMessage)
        }

        switch try await SharePlugin.presentSheet(sharing: items, title: title, from: presenter) {
        case .completed(let activityType):
            return ["activityType": activityType]
        case .canceled:
            throw CAPPluginError("Share canceled")
        case .failed(let error):
            throw CAPPluginError("Error sharing item", underlyingError: error)
        }
    }

    /// Presents a share sheet for `items` from `presenter` and returns how it closed: the first report of its
    /// completion handler, or `.canceled` when the sheet is released without one (the sheet holds the handler, so it
    /// can no longer report, for example after the app dismissed it). Throws when UIKit refuses the presentation (it
    /// logs and does nothing when the presenter is mid-transition or not in a window), which used to leave the call
    /// pending.
    @MainActor
    static func presentSheet(sharing items: [Any], title: String?, from presenter: UIViewController) async throws -> Outcome {
        var refused = false
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            let answer = OnceContinuation(continuation, fallback: Outcome.canceled)
            let actionController = UIActivityViewController(activityItems: items, applicationActivities: nil)

            if title != nil {
                actionController.setValue(title, forKey: "subject")
            }

            actionController.completionWithItemsHandler = { (activityType, completed, _ returnedItems, activityError) in
                if let activityError {
                    answer.resume(returning: .failed(activityError))
                } else if completed {
                    answer.resume(returning: .completed(activityType: activityType?.rawValue ?? ""))
                } else {
                    answer.resume(returning: .canceled)
                }
            }
            // `setCenteredPopover` anchors to the bridge view controller's view, which is not in
            // the presenter's hierarchy when presenting from a different view controller. Anchor
            // the popover to the presenting view controller's own view instead, centered and
            // without an arrow, matching `setCenteredPopover` behaviour.
            if let popover = actionController.popoverPresentationController, let presenterView = presenter.view {
                popover.sourceView = presenterView
                popover.sourceRect = CGRect(x: presenterView.bounds.midX, y: presenterView.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            presenter.present(actionController, animated: true, completion: nil)
            // UIKit sets presentedViewController as soon as it accepts a presentation.
            if presenter.presentedViewController !== actionController {
                refused = true
                answer.resume(returning: .canceled)
            }
        }
        if refused {
            throw CAPPluginError(noPresenterMessage)
        }
        return outcome
    }

    /// The items to share: the text, the URL and every file URL the call carries.
    static func activityItems(from call: CAPPluginCall) -> [Any] {
        var items = [Any]()

        if let text = call.getString("text") {
            items.append(text)
        }

        if let url = call.getString("url"), let urlObj = URL(string: url) {
            items.append(urlObj)
        }

        if let files = call.getArray("files") {
            files.forEach { file in
                if let url = file as? String, let fileUrl = URL(string: url) {
                    items.append(fileUrl)
                }
            }
        }
        return items
    }

    /// Whether a share sheet is already presented over `root`. Call on the main thread.
    static func isSharing(over root: UIViewController?) -> Bool {
        var presenter = root
        while let presented = presenter?.presentedViewController {
            if presented is UIActivityViewController {
                return true
            }
            presenter = presented
        }
        return false
    }

    /// The view controller to present from: the last controller in the chain presented over `root`, skipping one that
    /// is being dismissed, which cannot present. Call on the main thread.
    static func topmostPresenter(from root: UIViewController?) -> UIViewController? {
        var presenter = root
        while let presented = presenter?.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        return presenter
    }
}

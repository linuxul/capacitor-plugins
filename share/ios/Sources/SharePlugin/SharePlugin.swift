import Foundation
import Capacitor
import UIKit

@objc(SharePlugin)
public class SharePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SharePlugin"
    public let jsName = "Share"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("canShare", SharePlugin.canShare),
        .promise("share", SharePlugin.share)
    ]

    func canShare(_ call: CAPPluginCall) {
        call.resolve([
            "value": true
        ])
    }

    func share(_ call: CAPPluginCall) {
        let items = SharePlugin.activityItems(from: call)
        if items.count == 0 {
            call.reject("Must provide at least url, text or files")
            return
        }
        let title = call.getString("title")

        DispatchQueue.main.async { [weak self] in
            let root = self?.bridge?.viewController
            // A share is only in progress when a share sheet is already presented.
            if SharePlugin.isSharing(over: root) {
                call.reject("Can't share while sharing is in progress")
                return
            }
            // Present from the topmost presented view controller so the share sheet appears
            // above any view controller the app has presented over the webview. With nothing
            // presented this resolves to the bridge view controller, i.e. unchanged behaviour.
            guard let presenter = SharePlugin.topmostPresenter(from: root) else {
                call.reject("Unable to display the share sheet: there is no view controller to present it from")
                return
            }

            let actionController = UIActivityViewController(activityItems: items, applicationActivities: nil)

            if title != nil {
                actionController.setValue(title, forKey: "subject")
            }

            actionController.completionWithItemsHandler = { (activityType, completed, _ returnedItems, activityError) in
                if activityError != nil {
                    call.reject("Error sharing item", nil, activityError)
                    return
                }

                if completed {
                    call.resolve([
                        "activityType": activityType?.rawValue ?? ""
                    ])
                } else {
                    call.reject("Share canceled")
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
        }
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

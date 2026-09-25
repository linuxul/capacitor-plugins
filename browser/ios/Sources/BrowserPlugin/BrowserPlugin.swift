import Foundation
import Capacitor
import UIKit

@objc(CAPBrowserPlugin)
public class CAPBrowserPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CAPBrowserPlugin"
    public let jsName = "Browser"
    public let pluginMethods: [CAPPluginMethod] = [
        .promise("open", CAPBrowserPlugin.open),
        .promise("close", CAPBrowserPlugin.close)
    ]
    private let implementation = Browser()

    func open(_ call: CAPPluginCall) {
        // validate the URL
        guard let urlString = call.getString("url"), let url = URL(string: urlString) else {
            call.reject("Must provide a valid URL to open")
            return
        }
        // extract the optional parameters
        var color: UIColor?
        if let toolbarColor = call.getString("toolbarColor") {
            color = UIColor.capacitor.color(fromHex: toolbarColor)
        }
        let style = self.presentationStyle(for: call.getString("presentationStyle"))
        var popoverSize: CGSize?
        if let width = call.getInt("width"), let height = call.getInt("height") {
            popoverSize = CGSize(width: width, height: height)
        }
        // SFSafariViewController is a UIKit object: create and present it on the main queue, not the bridge queue.
        DispatchQueue.main.async { [weak self] in
            guard let self, let presenter = Self.topmostPresenter(from: self.bridge?.viewController) else {
                call.reject("Unable to display URL: there is no view controller to present it from")
                return
            }
            // prepare for display
            guard self.implementation.prepare(for: url, withTint: color, modalPresentation: style),
                  let viewController = self.implementation.viewController else {
                call.reject("Unable to display URL")
                return
            }
            self.implementation.browserEventDidOccur = { [weak self] (event) in
                self?.handle(event)
            }
            // display
            if style == .popover {
                Self.centerPopover(viewController, on: presenter, size: popoverSize)
            }
            presenter.present(viewController, animated: true, completion: {
                call.resolve()
            })
        }
    }

    func close(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let viewController = self.implementation.viewController else {
                call.reject("No active window to close!")
                return
            }
            // Dismiss only the browser: dismissing from the bridge view controller would also dismiss any controller
            // the app presented under it, and never completes when the browser is not presented any more.
            guard let presenter = viewController.presentingViewController else {
                self.implementation.cleanup()
                call.resolve()
                return
            }
            presenter.dismiss(animated: true) { [weak self] in
                call.resolve()
                self?.implementation.cleanup()
            }
        }
    }

    /// Reports a browser event, dismissing the browser first when it finished while still presented. Runs on the main
    /// thread, where SFSafariViewController and UIKit call their delegates.
    private func handle(_ event: BrowserEvent) {
        guard event == .finished, let presenter = implementation.viewController?.presentingViewController else {
            notifyListeners(event.listenerEvent, data: nil)
            return
        }
        presenter.dismiss(animated: true) { [weak self] in
            self?.notifyListeners(event.listenerEvent, data: nil)
        }
    }

    private func presentationStyle(for style: String?) -> UIModalPresentationStyle {
        if let style = style, style == "popover" {
            return .popover
        }
        return .fullScreen
    }
}

extension CAPBrowserPlugin {
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

    /// Centers the popover of `controller` on the view of `presenter`, without an arrow, and applies `size` when given.
    /// The anchor has to be in the presenter's hierarchy, which the bridge view controller's view is not when a
    /// full-screen modal covers it. Call on the main thread.
    static func centerPopover(_ controller: UIViewController, on presenter: UIViewController, size: CGSize?) {
        if let size {
            controller.preferredContentSize = size
        }
        guard let popover = controller.popoverPresentationController, let view = presenter.view else {
            return
        }
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
}

private extension BrowserEvent {
    var listenerEvent: String {
        switch self {
        case .loaded:
            return "browserPageLoaded"
        case .finished:
            return "browserFinished"
        }
    }
}

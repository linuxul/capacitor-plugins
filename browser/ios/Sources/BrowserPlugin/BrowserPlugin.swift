import Foundation
import Capacitor
import UIKit

@objc(CAPBrowserPlugin)
public class CAPBrowserPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CAPBrowserPlugin"
    public let jsName = "Browser"
    public let pluginMethods: [CAPPluginMethod] = [
        .async("open", CAPBrowserPlugin.open),
        .async("close", CAPBrowserPlugin.close)
    ]
    static let noPresenterMessage = "Unable to display URL: there is no view controller to present it from"
    private let implementation = Browser()

    /// SFSafariViewController is UIKit: the method runs on the main actor and returns once the browser is on screen.
    @MainActor
    func open(_ call: CAPPluginCall) async throws {
        // validate the URL
        guard let urlString = call.getString("url"), let url = URL(string: urlString) else {
            throw CAPPluginError("Must provide a valid URL to open")
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
        guard let presenter = Self.topmostPresenter(from: bridge?.viewController) else {
            throw CAPPluginError(Self.noPresenterMessage)
        }
        // prepare for display
        guard implementation.prepare(for: url, withTint: color, modalPresentation: style),
              let viewController = implementation.viewController else {
            throw CAPPluginError("Unable to display URL")
        }
        implementation.browserEventDidOccur = { [weak self] (event) in
            self?.handle(event)
        }
        // display
        if style == .popover {
            Self.centerPopover(viewController, on: presenter, size: popoverSize)
        }
        guard await Self.present(viewController, from: presenter) else {
            // Forget the browser UIKit did not show, or every later open would fail as if a browser were open.
            cleanUp(viewController)
            throw CAPPluginError(Self.noPresenterMessage)
        }
    }

    /// Dismisses the browser and returns once it is gone.
    @MainActor
    func close(_ call: CAPPluginCall) async throws {
        guard let viewController = implementation.viewController else {
            throw CAPPluginError("No active window to close!")
        }
        // Dismiss only the browser: dismissing from the bridge view controller would also dismiss any controller
        // the app presented under it, and never completes when the browser is not presented any more.
        if let presenter = viewController.presentingViewController {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // UIKit calls the completion once; should it drop it instead, releasing it still answers.
                let answer = OnceContinuation(continuation, fallback: ())
                presenter.dismiss(animated: true) {
                    answer.resume(returning: ())
                }
            }
        }
        cleanUp(viewController)
    }

    /// Forgets `viewController` unless another browser has replaced it meanwhile.
    @MainActor
    private func cleanUp(_ viewController: UIViewController) {
        if implementation.viewController === viewController {
            implementation.cleanup()
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
    /// Presents `controller` from `presenter` and returns once the presentation has completed: true, or false right
    /// away when UIKit refuses it (it logs and does nothing when the presenter is mid-transition or not in a window,
    /// which used to leave the call pending). UIKit sets `presentedViewController` as soon as it accepts a presentation.
    @MainActor
    static func present(_ controller: UIViewController, from presenter: UIViewController) async -> Bool {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let presented = OnceContinuation(continuation, fallback: true)
            presenter.present(controller, animated: true) {
                presented.resume(returning: true)
            }
            if presenter.presentedViewController !== controller {
                presented.resume(returning: false)
            }
        }
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

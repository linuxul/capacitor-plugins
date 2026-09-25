import Foundation
import SafariServices
import UIKit

@objc public enum BrowserEvent: Int {
    case loaded
    case finished
}

@objc public class Browser: NSObject, SFSafariViewControllerDelegate, UIPopoverPresentationControllerDelegate {
    private var safariViewController: SFSafariViewController?
    public typealias BrowserEventCallback = (BrowserEvent) -> Void

    @objc public var browserEventDidOccur: BrowserEventCallback?
    @objc var viewController: UIViewController? {
        return safariViewController
    }

    /// Creates the Safari view controller for `url`. Returns false when a browser is already open or the URL is not
    /// http(s). Call on the main thread: it creates and configures UIKit objects.
    @objc public func prepare(for url: URL, withTint tint: UIColor? = nil, modalPresentation style: UIModalPresentationStyle = .fullScreen) -> Bool {
        guard safariViewController == nil, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return false
        }
        let safariVC = SFSafariViewController(url: url)
        safariVC.delegate = self
        if let color = tint {
            safariVC.preferredBarTintColor = color
        }
        safariVC.modalPresentationStyle = style
        if style == .popover {
            safariVC.popoverPresentationController?.delegate = self
        }
        safariViewController = safariVC
        return true
    }

    @objc public func cleanup() {
        safariViewController = nil
    }

    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        finish()
    }

    public func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
        browserEventDidOccur?(.loaded)
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish()
    }

    public func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        finish()
    }

    /// Reports the end of the browser session once, even when UIKit reports the dismissal of a popover through both
    /// the current and the deprecated delegate method.
    private func finish() {
        guard safariViewController != nil else {
            return
        }
        browserEventDidOccur?(.finished)
        safariViewController = nil
    }
}

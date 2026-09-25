import Foundation
import Capacitor
import UIKit

public class StatusBar {

    // Weak: the bridge owns the plugin that owns this object. A strong reference closed a cycle that kept the bridge,
    // its web view and every plugin alive after the bridge view controller went away.
    private weak var bridge: CAPBridgeProtocol?
    private var isOverlayingWebview = true
    private var backgroundColor = UIColor.black
    private var backgroundView: UIView?
    private var observers: [NSObjectProtocol] = []

    init(bridge: CAPBridgeProtocol, config: StatusBarConfig) {
        self.bridge = bridge
        setupObservers(with: config)
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func setupObservers(with config: StatusBarConfig) {
        observers.append(NotificationCenter.default.addObserver(forName: .capacitorViewDidAppear, object: .none, queue: .none) { [weak self] _ in
            self?.handleViewDidAppear(config: config)
        })
        observers.append(NotificationCenter.default.addObserver(forName: .capacitorStatusBarTapped, object: .none, queue: .none) { [weak self] _ in
            self?.bridge?.triggerJSEvent(eventName: "statusTap", target: "window")
        })
        observers.append(NotificationCenter.default.addObserver(forName: .capacitorViewWillTransition, object: .none, queue: .none) { [weak self] _ in
            self?.handleViewWillTransition()
        })
    }

    private func handleViewDidAppear(config: StatusBarConfig) {
        setStyle(config.style)
        setBackgroundColor(config.backgroundColor)
        setOverlaysWebView(config.overlaysWebView)
    }

    private func handleViewWillTransition() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.resizeStatusBarBackgroundView()
            self?.resizeWebView()
        }
    }

    func setStyle(_ style: UIStatusBarStyle) {
        bridge?.statusBarStyle = style
    }

    func setBackgroundColor(_ color: UIColor) {
        backgroundColor = color
        backgroundView?.backgroundColor = color
    }

    func setAnimation(_ animation: String) {
        if animation == "SLIDE" {
            bridge?.statusBarAnimation = .slide
        } else if animation == "NONE" {
            bridge?.statusBarAnimation = .none
        } else {
            bridge?.statusBarAnimation = .fade
        }
    }

    func hide(animation: String) {
        setAnimation(animation)
        guard let bridge, bridge.statusBarVisible else {
            return
        }
        bridge.statusBarVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.resizeWebView()
            self?.backgroundView?.removeFromSuperview()
            self?.backgroundView?.isHidden = true
        }
    }

    func show(animation: String) {
        setAnimation(animation)
        guard let bridge, !bridge.statusBarVisible else {
            return
        }
        bridge.statusBarVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else {
                return
            }
            self.resizeWebView()
            if !self.isOverlayingWebview, let backgroundView = self.backgroundView {
                self.resizeStatusBarBackgroundView()
                self.bridge?.webView?.superview?.addSubview(backgroundView)
            }
            self.backgroundView?.isHidden = false
        }
    }

    func getInfo() -> StatusBarInfo {
        let style: String
        switch bridge?.statusBarStyle ?? .default {
        case .default:
            style = "DEFAULT"
        case .lightContent:
            style = "DARK"
        case .darkContent:
            style = "LIGHT"
        @unknown default:
            style = "DEFAULT"
        }

        return StatusBarInfo(
            overlays: isOverlayingWebview,
            visible: bridge?.statusBarVisible ?? false,
            style: style,
            color: UIColor.capacitor.hex(fromColor: backgroundColor),
            height: getStatusBarFrame().size.height
        )
    }

    func setOverlaysWebView(_ overlay: Bool) {
        if overlay == isOverlayingWebview { return }
        isOverlayingWebview = overlay
        if overlay {
            backgroundView?.removeFromSuperview()
        } else {
            bridge?.webView?.superview?.addSubview(backgroundViewCreatingIfNeeded())
        }
        resizeWebView()
    }

    private func resizeWebView() {
        guard
            let bridge,
            let webView = bridge.webView,
            let bounds = bridge.viewController?.view.window?.windowScene?.keyWindow?.bounds
        else { return }
        bridge.viewController?.view.frame = bounds
        webView.frame = bounds
        let statusBarHeight = getStatusBarFrame().size.height
        var webViewFrame = webView.frame

        if isOverlayingWebview {
            let safeAreaTop = webView.safeAreaInsets.top
            if statusBarHeight >= safeAreaTop && safeAreaTop > 0 {
                webViewFrame.origin.y = safeAreaTop == 40 ? 20 : statusBarHeight - safeAreaTop
            } else {
                webViewFrame.origin.y = 0
            }
        } else {
            webViewFrame.origin.y = statusBarHeight
        }
        webViewFrame.size.height -= webViewFrame.origin.y
        webView.frame = webViewFrame
    }

    private func resizeStatusBarBackgroundView() {
        backgroundView?.frame = getStatusBarFrame()
    }

    private func getStatusBarFrame() -> CGRect {
        return bridge?.viewController?.view.window?.windowScene?.statusBarManager?.statusBarFrame ?? .zero
    }

    private func backgroundViewCreatingIfNeeded() -> UIView {
        if let backgroundView {
            return backgroundView
        }
        let view = UIView(frame: getStatusBarFrame())
        view.backgroundColor = backgroundColor
        view.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        view.isHidden = !(bridge?.statusBarVisible ?? false)
        backgroundView = view
        return view
    }
}

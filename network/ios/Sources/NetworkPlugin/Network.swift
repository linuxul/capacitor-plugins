import Foundation
import Network

public typealias NetworkConnectionChangedObserver = (Network.Connection) -> Void

/// Follows the device's network path with NWPathMonitor, which replaces the copy of the SCNetworkReachability-based
/// Reachability library the plugin used to carry.
public class Network {
    public enum NetworkError: Error {
        case initializationFailed
    }
    public enum Connection {
        case unavailable, wifi, cellular
    }

    /// Called on the main queue with the first status and with every change after it.
    var statusObserver: NetworkConnectionChangedObserver?

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    // The latest status the monitor reported, nil until its first report.
    private var latest: Connection?
    // getStatus calls made before the first report.
    private var pendingStatusRequests: [(Connection) -> Void] = []

    init() throws {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(Network.connection(for: path))
        }
        monitor.start(queue: DispatchQueue(label: "com.capacitorjs.plugins.network.monitor"))
    }

    deinit {
        monitor.cancel()
    }

    /// The latest status, or `.unavailable` before the monitor has reported one.
    func currentStatus() -> Network.Connection {
        return lock.withLock { latest ?? .unavailable }
    }

    /// Calls `completion` with the current status: right away once the monitor has reported one, otherwise with its
    /// first report, which follows right after it starts.
    func currentStatus(_ completion: @escaping (Network.Connection) -> Void) {
        let known: Connection? = lock.withLock {
            if latest == nil {
                pendingStatusRequests.append(completion)
            }
            return latest
        }
        if let known {
            completion(known)
        }
    }

    /// The status a path gives. A satisfied path, or one that a new connection would bring up (an on-demand VPN, a
    /// cellular data context that is not active yet), is connected: over cellular when it uses a cellular interface and
    /// no Wi-Fi, and as "wifi" otherwise, including wired Ethernet, the way the reachability flags reported every
    /// reachable route that was not WWAN.
    static func connection(status: NWPath.Status, usesWiFi: Bool, usesCellular: Bool) -> Connection {
        switch status {
        case .satisfied, .requiresConnection:
            return usesCellular && !usesWiFi ? .cellular : .wifi
        case .unsatisfied:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    private static func connection(for path: NWPath) -> Connection {
        return connection(status: path.status, usesWiFi: path.usesInterfaceType(.wifi), usesCellular: path.usesInterfaceType(.cellular))
    }

    /// Records a report from the monitor. The observer hears the first status and every change after it, on the main
    /// queue like the reachability notifications; path updates that leave the status unchanged are not reported.
    private func update(_ connection: Connection) {
        let (waiting, changed): ([(Connection) -> Void], Bool) = lock.withLock {
            let changed = latest != connection
            latest = connection
            defer { pendingStatusRequests = [] }
            return (pendingStatusRequests, changed)
        }
        waiting.forEach { $0(connection) }
        guard changed else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.statusObserver?(connection)
        }
    }
}

import Foundation
import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var quality: TelefamNetworkQuality = .online

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.telefam.company.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let next: TelefamNetworkQuality = (path.status == .satisfied) ? .online : .offline
            Task { @MainActor [weak self] in
                self?.quality = next
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

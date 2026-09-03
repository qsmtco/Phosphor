import SwiftUI
import Network

// MARK: - ConnectivityMonitor
// (Adapted from Eagle Timeclock's proven pattern - qsmtco internal reuse.)

@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published var isOnline: Bool = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.qsmtco.phosphor.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - App Entry Point

@main
struct PhosphorApp: App {
    @StateObject private var connectivity = ConnectivityMonitor()
    @State private var reloadToken = 0

    var body: some Scene {
        WindowGroup {
            ZStack {
                ShellView(reloadToken: reloadToken)
                    .id(reloadToken)
                    .ignoresSafeArea()
                if !connectivity.isOnline {
                    OfflineView(onRetry: { reloadToken += 1 })
                }
            }
        }
    }
}

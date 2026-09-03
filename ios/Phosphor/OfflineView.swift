import SwiftUI

// MARK: - OfflineView
//
// Displayed when ConnectivityMonitor detects no active network connection.
// Provides a clean, prominent retry button to trigger a reload.

struct OfflineView: View {
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "wifi.slash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .foregroundColor(.secondary)

                Text("No connection")
                    .font(.title2.weight(.semibold))

                Text("Phosphor needs a connection to reach your agent server.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
            }
        }
    }
}

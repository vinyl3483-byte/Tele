import SwiftUI

@main
struct TelefamApp: App {
    @StateObject private var viewModel = TelefamViewModel()
    @StateObject private var network = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            Group {
                if let session = viewModel.session {
                    if !session.profile_completed {
                        ProfileSetupView(viewModel: viewModel, network: network)
                    } else {
                        WorkspaceView(viewModel: viewModel, network: network)
                    }
                } else {
                    AuthView(viewModel: viewModel)
                }
            }
            .preferredColorScheme(viewModel.isDarkTheme ? .dark : .light)
            .onOpenURL { url in
                guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
                    return
                }
                if let email = components.queryItems?.first(where: { $0.name == "email" })?.value {
                    viewModel.email = email
                }
                Task { await viewModel.verifyOTP(magicToken: token) }
            }
            .onChange(of: network.quality) { _, newQuality in
                if newQuality != .offline {
                    Task { await viewModel.syncAll(quality: newQuality) }
                }
            }
        }
    }
}

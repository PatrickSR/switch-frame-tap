// SPDX-License-Identifier: GPL-2.0-only
import SwiftUI
import UIKit

@main
struct SFTapApp: App {
    @State private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase
    private var session: StreamSession { StreamSession.shared }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(settings)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .defersSystemGestures(on: .all)
                .onAppear {
                    session.attach(settings: settings)
                    autoConnect()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background: session.suspend()
                    case .active: session.resume()
                    default: break
                    }
                }
                .onChange(of: session.phase) { _, phase in
                    UIApplication.shared.isIdleTimerDisabled = phase != .idle
                }
        }
    }

    private func autoConnect() {
#if DEBUG
        let defaults = UserDefaults.standard
        guard let host = defaults.string(forKey: "autoConnectHost"), !host.isEmpty else { return }
        let port = defaults.integer(forKey: "autoConnectPort")
        session.start(host: host, port: port > 0 ? port : 9950)
#endif
    }
}

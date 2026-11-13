// SPDX-License-Identifier: GPL-2.0-only
import SwiftUI

struct RootView: View {
    @Environment(StreamSession.self) private var session

    var body: some View {
        if session.phase == .idle {
            HomeView()
        } else {
            PlayerView()
        }
    }
}

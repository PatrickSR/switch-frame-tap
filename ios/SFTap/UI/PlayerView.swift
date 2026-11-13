// SPDX-License-Identifier: GPL-2.0-only
import SFTCore
import SwiftUI

struct PlayerView: View {
    @Environment(StreamSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @State private var showSettings = false
    @State private var menuDimmed = false
    @State private var dimTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoLayerView(displayLayer: session.displayLayer)
                .ignoresSafeArea()
            PadOverlay(
                opacity: settings.padOpacity,
                scale: settings.padScale,
                haptics: settings.haptics,
                hidden: settings.padHidden || showSettings,
                enabled: session.consoleTakesInput == true && !showSettings
            ) { state in
                session.padStateChanged(state)
            } onInteraction: {
                wakeMenu()
            }
            .ignoresSafeArea()
            if !session.hasRecentPicture {
                statusOverlay
            }
            if session.consoleTakesInput == false {
                VStack {
                    Spacer()
                    Text("在 Switch 的 Switch Frame Tap 应用 Beta 页开启「Controls from the viewer」后重启，才能用手柄操作")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(.bottom, 12)
                }
                .allowsHitTesting(false)
            }
            if settings.showStats {
                VStack {
                    HStack {
                        StatsOverlay()
                            .allowsHitTesting(false)
                        Spacer()
                    }
                    Spacer()
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showSettings = true
                        wakeMenu()
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 32))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .opacity(menuDimmed ? 0.3 : 1)
                    .background(.black.opacity(0.35), in: Circle())
                    .accessibilityLabel("播放设置")
                    Spacer()
                }
                .padding(.top, 6)
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { wakeMenu() }
        .onAppear { wakeMenu() }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(showDisconnect: true)
        }
        .onChange(of: showSettings) { _, value in session.setPadHidden(settings.padHidden || value) }
        .onChange(of: settings.muted) { _, value in session.setMuted(value) }
        .onChange(of: settings.audioPreset) { _, value in session.setAudioPreset(value) }
        .onChange(of: settings.padHidden) { _, value in session.setPadHidden(value || showSettings) }
    }

    private var statusOverlay: some View {
        VStack(spacing: 10) {
            switch session.phase {
            case .connecting(let attempt):
                ProgressView()
                Text(attempt <= 1 ? "连接中…" : "重连中（第 \(attempt) 次）")
            case .reconnecting(let attempt, let reason):
                ProgressView()
                Text("重连中（第 \(attempt) 次）：\(reason)")
                    .multilineTextAlignment(.center)
            case .waitingPicture:
                ProgressView()
                Text("已连接，等待画面…")
            case .playing:
                if session.consoleStatus == nil {
                    ProgressView()
                    Text("画面中断，等待恢复…")
                }
            case .idle:
                EmptyView()
            }
            if let status = session.consoleStatus {
                let text = ConsoleStatusText.chinese(for: status.reason)
                Text(text.head).font(.headline)
                if !text.detail.isEmpty {
                    Text(text.detail).font(.subheadline)
                }
                englishStatus(status)
            }
        }
        .foregroundStyle(.white)
        .tint(.white)
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(session.phase == .playing ? 0.35 : 0.75))
        .allowsHitTesting(false)
    }

    private func englishStatus(_ status: StatusPacket) -> some View {
        VStack(spacing: 2) {
            if !status.head.isEmpty {
                Text(status.head).font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            if !status.detail.isEmpty {
                Text(status.detail).font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func wakeMenu() {
        menuDimmed = false
        dimTask?.cancel()
        dimTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { menuDimmed = true }
        }
    }
}

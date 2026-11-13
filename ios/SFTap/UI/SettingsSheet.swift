// SPDX-License-Identifier: GPL-2.0-only
import SFTCore
import SwiftUI

struct SettingsSheet: View {
    @Environment(StreamSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var showDisconnect: Bool

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("音频") {
                    Toggle("静音", isOn: $settings.muted)
                    Picker("音频缓冲", selection: $settings.audioPreset) {
                        Text("低延迟 40 ms").tag(AudioJitterBuffer.Preset.low.rawValue)
                        Text("标准 80 ms").tag(AudioJitterBuffer.Preset.standard.rawValue)
                        Text("稳定 150 ms").tag(AudioJitterBuffer.Preset.stable.rawValue)
                    }
                }
                Section("手柄") {
                    VStack(alignment: .leading) {
                        Text("手柄透明度 \(Int(settings.padOpacity * 100))%")
                        Slider(value: $settings.padOpacity, in: 0.2 ... 1.0)
                    }
                    VStack(alignment: .leading) {
                        Text("手柄大小 \(Int(settings.padScale * 100))%")
                        Slider(value: $settings.padScale, in: 0.8 ... 1.3)
                    }
                    Toggle("触感反馈", isOn: $settings.haptics)
                    Toggle("隐藏手柄", isOn: $settings.padHidden)
                }
                Section("其他") {
                    Toggle("显示统计信息", isOn: $settings.showStats)
                }
                if showDisconnect {
                    Section {
                        Button("断开连接", role: .destructive) {
                            dismiss()
                            session.stop()
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// SPDX-License-Identifier: GPL-2.0-only
import SwiftUI

struct StatsOverlay: View {
    @Environment(StreamSession.self) private var session

    var body: some View {
        let stats = session.stats
        VStack(alignment: .leading, spacing: 2) {
            line("分辨率 \(stats.width)×\(stats.height)")
            line(String(format: "视频 %.0f fps · %.1f Mbps · 解码 %.1f ms", stats.fps, stats.mbps, stats.decodeMs))
            line(String(format: "主机延迟 %.0f ms · 接收→显示 p50 %.0f ms", stats.consoleAgeMs, stats.displayMs))
            line("重置 \(stats.resets) / 丢帧 \(stats.dropped)")
            line(String(format: "音频缓冲 %.0f ms · 欠载 %d · 丢弃 %.0f ms", stats.audioBufferedMs, stats.audioUnderruns, stats.audioDroppedMs))
            line("手柄：\(stats.padState)")
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 8)
        .padding(.leading, 8)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.white)
    }
}

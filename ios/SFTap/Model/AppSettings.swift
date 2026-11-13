// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Observation
import SFTCore

@Observable final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var host: String { didSet { defaults.set(host, forKey: "host") } }
    var port: Int { didSet { defaults.set(port, forKey: "port") } }
    var audioPreset: Int { didSet { defaults.set(audioPreset, forKey: "audioPreset") } }
    var padOpacity: Double { didSet { defaults.set(padOpacity, forKey: "padOpacity") } }
    var padScale: Double { didSet { defaults.set(padScale, forKey: "padScale") } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    var showStats: Bool { didSet { defaults.set(showStats, forKey: "showStats") } }
    var padHidden: Bool { didSet { defaults.set(padHidden, forKey: "padHidden") } }
    var muted: Bool { didSet { defaults.set(muted, forKey: "muted") } }

    init() {
        host = defaults.string(forKey: "host") ?? ""
        let storedPort = defaults.integer(forKey: "port")
        port = storedPort >= 1 && storedPort <= 65535 ? storedPort : 9950
        let preset = defaults.object(forKey: "audioPreset") as? Int
        audioPreset = preset ?? AudioJitterBuffer.Preset.standard.rawValue
        let opacity = defaults.object(forKey: "padOpacity") as? Double ?? 0.5
        padOpacity = min(max(opacity, 0.2), 1.0)
        let scale = defaults.object(forKey: "padScale") as? Double ?? 1.0
        padScale = min(max(scale, 0.8), 1.3)
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        showStats = defaults.bool(forKey: "showStats")
        padHidden = defaults.bool(forKey: "padHidden")
        muted = defaults.bool(forKey: "muted")
    }
}

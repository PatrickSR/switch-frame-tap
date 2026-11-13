// SPDX-License-Identifier: GPL-2.0-only
import SFTCore
import SwiftUI
import UIKit

struct PadOverlay: UIViewRepresentable {
    var opacity: Double
    var scale: Double
    var haptics: Bool
    var hidden: Bool
    var enabled: Bool
    var onChange: (PadState) -> Void
    var onInteraction: () -> Void

    func makeUIView(context: Context) -> VirtualPadView {
        let view = VirtualPadView(frame: .zero)
        view.onChange = onChange
        view.onInteraction = onInteraction
        return view
    }

    func updateUIView(_ view: VirtualPadView, context: Context) {
        view.padOpacity = opacity
        view.padScale = scale
        view.haptics = haptics
        view.isHidden = hidden
        view.isUserInteractionEnabled = enabled
        view.onChange = onChange
        view.onInteraction = onInteraction
        if hidden || !enabled { view.releaseAll() }
    }

    static func dismantleUIView(_ view: VirtualPadView, coordinator: ()) {
        view.releaseAll()
    }
}

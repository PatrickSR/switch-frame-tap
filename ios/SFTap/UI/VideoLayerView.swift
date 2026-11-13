// SPDX-License-Identifier: GPL-2.0-only
import AVFoundation
import QuartzCore
import SwiftUI
import UIKit

final class VideoLayerHostView: UIView {
    let displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        backgroundColor = .black
        displayLayer.frame = bounds
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}

struct VideoLayerView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> VideoLayerHostView {
        VideoLayerHostView(displayLayer: displayLayer)
    }

    func updateUIView(_ view: VideoLayerHostView, context: Context) {}
}

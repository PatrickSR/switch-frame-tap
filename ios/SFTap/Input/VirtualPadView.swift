// SPDX-License-Identifier: GPL-2.0-only
import SFTCore
import UIKit

final class VirtualPadView: UIView {
    var onChange: ((PadState) -> Void)?
    var onInteraction: (() -> Void)?
    var padOpacity: CGFloat = 0.5 { didSet { setNeedsDisplay() } }
    var padScale: CGFloat = 1.0 { didSet { setNeedsLayout() } }
    var haptics = true

    private enum Active {
        case button(PadButtons)
        case face(PadButtons)
        case dpad(PadButtons)
        case stick(isLeft: Bool, base: CGPoint, dx: CGFloat, dy: CGFloat)
    }

    private struct Layout {
        var leftStickHome = CGPoint.zero
        var rightStickHome = CGPoint.zero
        var stickRadius: CGFloat = 60
        var dpadCenter = CGPoint.zero
        var dpadRadius: CGFloat = 55
        var dpadRect = CGRect.zero
        var abxyCenter = CGPoint.zero
        var abxyRadius: CGFloat = 52
        var buttonRadius: CGFloat = 26
        var abxyRect = CGRect.zero
        var leftZone = CGRect.zero
        var rightZone = CGRect.zero
        var circles: [(button: PadButtons, label: String, center: CGPoint, radius: CGFloat)] = []
        var pads: [(button: PadButtons, label: String, rect: CGRect)] = []
    }

    private var active: [ObjectIdentifier: Active] = [:]
    private var state = PadState()
    private var generator = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        generator.prepare()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        generator.prepare()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    private func layout() -> Layout {
        var layout = Layout()
        let bounds = self.bounds
        let insets = safeAreaInsets
        let width = bounds.width
        let height = bounds.height
        let left = insets.left
        let right = insets.right
        let top = insets.top
        let bottom = insets.bottom
        let scale = min(padScale, (width - left - right) / 640, (height - top - bottom) / 340)

        layout.stickRadius = 60 * scale
        layout.dpadRadius = 55 * scale
        layout.abxyRadius = 52 * scale
        layout.buttonRadius = max(22, 26 * scale)
        layout.leftStickHome = CGPoint(x: left + 85 * scale, y: height - bottom - 180 * scale)
        layout.rightStickHome = CGPoint(x: width - right - 85 * scale, y: height - bottom - 75 * scale)
        layout.dpadCenter = CGPoint(x: left + 180 * scale, y: height - bottom - 65 * scale)
        layout.dpadRect = CGRect(
            x: layout.dpadCenter.x - layout.dpadRadius - 8,
            y: layout.dpadCenter.y - layout.dpadRadius - 8,
            width: (layout.dpadRadius + 8) * 2,
            height: (layout.dpadRadius + 8) * 2
        )
        layout.abxyCenter = CGPoint(x: width - right - 85 * scale, y: height - bottom - 230 * scale)
        let faceSpan = layout.abxyRadius + layout.buttonRadius + 10
        layout.abxyRect = CGRect(
            x: layout.abxyCenter.x - faceSpan,
            y: layout.abxyCenter.y - faceSpan,
            width: faceSpan * 2,
            height: faceSpan * 2
        )
        layout.leftZone = CGRect(x: left, y: top + 80, width: width * 0.4 - left, height: height - top - bottom - 80)
        layout.rightZone = CGRect(x: width * 0.6, y: height - bottom - 145 * scale, width: width * 0.4 - right, height: 145 * scale)

        let padWidth = 90 * scale
        let padHeight = max(44, 36 * scale)
        layout.pads = [
            (.zl, "ZL", CGRect(x: left + 14, y: top + 10, width: padWidth, height: padHeight)),
            (.l, "L", CGRect(x: left + 24 + padWidth, y: top + 10, width: padWidth, height: padHeight)),
            (.zr, "ZR", CGRect(x: width - right - 14 - padWidth, y: top + 10, width: padWidth, height: padHeight)),
            (.r, "R", CGRect(x: width - right - 24 - padWidth * 2, y: top + 10, width: padWidth, height: padHeight))
        ]
        let small = 17 * scale
        layout.circles = [
            (.minus, "−", CGPoint(x: width / 2 - 90, y: top + 30), small),
            (.plus, "+", CGPoint(x: width / 2 + 90, y: top + 30), small),
            (.capture, "截图", CGPoint(x: width / 2 - 52, y: height - bottom - 32), small),
            (.home, "HOME", CGPoint(x: width / 2 + 52, y: height - bottom - 32), 20 * scale),
            (.l3, "L3", CGPoint(x: left + 170 * scale, y: height - bottom - 175 * scale), small),
            (.r3, "R3", CGPoint(x: width - right - 170 * scale, y: height - bottom - 120 * scale), small)
        ]
        return layout
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let layout = layout()
        let held = heldButtons()
        let fillBase = UIColor(white: 0.15, alpha: padOpacity * 0.55)
        let fillPressed = UIColor.systemGreen.withAlphaComponent(min(padOpacity * 0.95, 1))
        let stroke = UIColor.white.withAlphaComponent(padOpacity * 0.7)
        let label = UIColor.white.withAlphaComponent(min(padOpacity + 0.25, 1))

        func circle(_ center: CGPoint, _ radius: CGFloat, pressed: Bool, text: String, fontSize: CGFloat) {
            let path = UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            (pressed ? fillPressed : fillBase).setFill()
            stroke.setStroke()
            path.lineWidth = 1.5
            path.fill()
            path.stroke()
            drawText(text, at: center, size: fontSize, color: label, context: context)
        }

        for entry in layout.circles {
            circle(entry.center, entry.radius, pressed: held.contains(entry.button), text: entry.label, fontSize: entry.label.count > 2 ? 9 : 12)
        }
        for entry in layout.pads {
            let path = UIBezierPath(roundedRect: entry.rect, cornerRadius: 10)
            (held.contains(entry.button) ? fillPressed : fillBase).setFill()
            stroke.setStroke()
            path.lineWidth = 1.5
            path.fill()
            path.stroke()
            drawText(entry.label, at: CGPoint(x: entry.rect.midX, y: entry.rect.midY), size: 12, color: label, context: context)
        }

        let dpadPressed = held.intersection([.up, .down, .left, .right])
        let dpadPath = UIBezierPath(ovalIn: CGRect(
            x: layout.dpadCenter.x - layout.dpadRadius,
            y: layout.dpadCenter.y - layout.dpadRadius,
            width: layout.dpadRadius * 2,
            height: layout.dpadRadius * 2
        ))
        (dpadPressed.isEmpty ? fillBase : fillPressed).setFill()
        stroke.setStroke()
        dpadPath.lineWidth = 1.5
        dpadPath.fill()
        dpadPath.stroke()
        drawDpadCross(at: layout.dpadCenter, radius: layout.dpadRadius, color: label, context: context)

        let c = layout.abxyCenter
        let r = layout.abxyRadius
        let faces: [(PadButtons, String, CGPoint)] = [
            (.x, "X", CGPoint(x: c.x, y: c.y - r)),
            (.a, "A", CGPoint(x: c.x + r, y: c.y)),
            (.b, "B", CGPoint(x: c.x, y: c.y + r)),
            (.y, "Y", CGPoint(x: c.x - r, y: c.y))
        ]
        for (button, text, center) in faces {
            circle(center, layout.buttonRadius, pressed: held.contains(button), text: text, fontSize: 15)
        }

        drawStick(layout: layout, isLeft: true, fill: fillBase, stroke: stroke, context: context)
        drawStick(layout: layout, isLeft: false, fill: fillBase, stroke: stroke, context: context)
    }

    private func drawStick(layout: Layout, isLeft: Bool, fill: UIColor, stroke: UIColor, context: CGContext) {
        var base = isLeft ? layout.leftStickHome : layout.rightStickHome
        var knob = base
        for (_, item) in active {
            if case .stick(let left, let stickBase, let dx, let dy) = item, left == isLeft {
                base = stickBase
                knob = CGPoint(x: base.x + dx * layout.stickRadius, y: base.y + dy * layout.stickRadius)
            }
        }
        let basePath = UIBezierPath(ovalIn: CGRect(
            x: base.x - layout.stickRadius,
            y: base.y - layout.stickRadius,
            width: layout.stickRadius * 2,
            height: layout.stickRadius * 2
        ))
        UIColor(white: 0.15, alpha: padOpacity * 0.3).setFill()
        stroke.setStroke()
        basePath.lineWidth = 1.5
        basePath.fill()
        basePath.stroke()
        let knobRadius = layout.stickRadius * 0.45
        let knobPath = UIBezierPath(ovalIn: CGRect(
            x: knob.x - knobRadius,
            y: knob.y - knobRadius,
            width: knobRadius * 2,
            height: knobRadius * 2
        ))
        fill.setFill()
        knobPath.fill()
        knobPath.stroke()
    }

    private func drawDpadCross(at center: CGPoint, radius: CGFloat, color: UIColor, context: CGContext) {
        let arm = radius * 0.45
        let width = radius * 0.28
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x - width, y: center.y - arm))
        path.addLine(to: CGPoint(x: center.x + width, y: center.y - arm))
        path.addLine(to: CGPoint(x: center.x + width, y: center.y - width))
        path.addLine(to: CGPoint(x: center.x + arm, y: center.y - width))
        path.addLine(to: CGPoint(x: center.x + arm, y: center.y + width))
        path.addLine(to: CGPoint(x: center.x + width, y: center.y + width))
        path.addLine(to: CGPoint(x: center.x + width, y: center.y + arm))
        path.addLine(to: CGPoint(x: center.x - width, y: center.y + arm))
        path.addLine(to: CGPoint(x: center.x - width, y: center.y + width))
        path.addLine(to: CGPoint(x: center.x - arm, y: center.y + width))
        path.addLine(to: CGPoint(x: center.x - arm, y: center.y - width))
        path.addLine(to: CGPoint(x: center.x - width, y: center.y - arm))
        path.close()
        color.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawText(_ text: String, at center: CGPoint, size: CGFloat, color: UIColor, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color
        ]
        let drawn = NSAttributedString(string: text, attributes: attributes)
        let bounds = drawn.size()
        drawn.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onInteraction?()
        let layout = layout()
        for touch in touches {
            let point = touch.location(in: self)
            let id = ObjectIdentifier(touch)
            if let face = faceButton(at: point, layout: layout), inFaceGroup(point, layout: layout) {
                active[id] = .face(face)
                if !face.isEmpty { impact() }
            } else if let pad = layout.pads.first(where: { $0.rect.insetBy(dx: -6, dy: -6).contains(point) }) {
                active[id] = .button(pad.button)
                impact()
            } else if let circle = layout.circles.first(where: {
                hypot($0.center.x - point.x, $0.center.y - point.y) <= max($0.radius + 10, 22)
            }) {
                active[id] = .button(circle.button)
                impact()
            } else if layout.dpadRect.contains(point) || hypot(layout.dpadCenter.x - point.x, layout.dpadCenter.y - point.y) <= layout.dpadRadius {
                active[id] = .dpad(dpadButtons(at: point, layout: layout))
            } else if layout.leftZone.contains(point) && !layout.dpadRect.contains(point) {
                if !hasStick(isLeft: true) { active[id] = .stick(isLeft: true, base: point, dx: 0, dy: 0) }
            } else if layout.rightZone.contains(point) && !layout.abxyRect.contains(point) {
                if !hasStick(isLeft: false) { active[id] = .stick(isLeft: false, base: point, dx: 0, dy: 0) }
            }
        }
        recompute()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let layout = layout()
        var changed = false
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let item = active[id] else { continue }
            let point = touch.location(in: self)
            switch item {
            case .button:
                break
            case .face(let previous):
                let face = faceButton(at: point, layout: layout) ?? []
                if face != previous {
                    active[id] = .face(face)
                    if !face.isEmpty { impact() }
                    changed = true
                }
            case .dpad(let previous):
                let buttons = dpadButtons(at: point, layout: layout)
                if buttons != previous {
                    active[id] = .dpad(buttons)
                    changed = true
                }
            case .stick(let isLeft, let base, let dx, let dy):
                var vector = CGPoint(x: (point.x - base.x) / layout.stickRadius, y: (point.y - base.y) / layout.stickRadius)
                let length = hypot(vector.x, vector.y)
                if length > 1 {
                    vector = CGPoint(x: vector.x / length, y: vector.y / length)
                }
                if vector.x != dx || vector.y != dy {
                    active[id] = .stick(isLeft: isLeft, base: base, dx: vector.x, dy: vector.y)
                    changed = true
                }
            }
        }
        if changed { recompute() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches {
            active.removeValue(forKey: ObjectIdentifier(touch))
        }
        recompute()
    }

    private func inFaceGroup(_ point: CGPoint, layout: Layout) -> Bool {
        hypot(point.x - layout.abxyCenter.x, point.y - layout.abxyCenter.y) <= layout.abxyRadius + layout.buttonRadius + 8
    }

    private func faceButton(at point: CGPoint, layout: Layout) -> PadButtons? {
        guard inFaceGroup(point, layout: layout) else { return nil }
        let c = layout.abxyCenter
        let r = layout.abxyRadius
        let faces: [(PadButtons, CGPoint)] = [
            (.x, CGPoint(x: c.x, y: c.y - r)),
            (.a, CGPoint(x: c.x + r, y: c.y)),
            (.b, CGPoint(x: c.x, y: c.y + r)),
            (.y, CGPoint(x: c.x - r, y: c.y))
        ]
        for (button, center) in faces where hypot(point.x - center.x, point.y - center.y) <= layout.buttonRadius {
            return button
        }
        return []
    }

    private func dpadButtons(at point: CGPoint, layout: Layout) -> PadButtons {
        let dx = point.x - layout.dpadCenter.x
        let dy = point.y - layout.dpadCenter.y
        let distance = hypot(dx, dy)
        guard distance > layout.dpadRadius * 0.3 else { return [] }
        let angle = atan2(dy, dx) * 180 / .pi
        switch angle {
        case -22.5 ..< 22.5: return .right
        case 22.5 ..< 67.5: return [.right, .down]
        case 67.5 ..< 112.5: return .down
        case 112.5 ..< 157.5: return [.left, .down]
        case -157.5 ..< -112.5: return [.left, .up]
        case -112.5 ..< -67.5: return .up
        case -67.5 ..< -22.5: return [.right, .up]
        default: return .left
        }
    }

    private func hasStick(isLeft: Bool) -> Bool {
        active.values.contains {
            if case .stick(let left, _, _, _) = $0 { return left == isLeft }
            return false
        }
    }

    private func heldButtons() -> PadButtons {
        var buttons: PadButtons = []
        for (_, item) in active {
            switch item {
            case .button(let button): buttons.insert(button)
            case .face(let button): buttons.formUnion(button)
            case .dpad(let button): buttons.formUnion(button)
            case .stick: break
            }
        }
        return buttons
    }

    private func recompute() {
        let buttons = heldButtons()
        var left: (x: CGFloat, y: CGFloat) = (0, 0)
        var right: (x: CGFloat, y: CGFloat) = (0, 0)
        for (_, item) in active {
            if case .stick(let isLeft, _, let dx, let dy) = item {
                if isLeft { left = (dx, dy) } else { right = (dx, dy) }
            }
        }
        let (lx, ly) = PadState.normalizedStick(x: Double(left.x), y: Double(left.y))
        let (rx, ry) = PadState.normalizedStick(x: Double(right.x), y: Double(right.y))
        let next = PadState(buttons: buttons, lx: lx, ly: ly, rx: rx, ry: ry)
        if next != state {
            state = next
            onChange?(next)
        }
    }

    func releaseAll() {
        active.removeAll()
        recompute()
    }

    private func impact() {
        guard haptics else { return }
        generator.impactOccurred()
    }
}

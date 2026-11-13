// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import SFTCore

final class PadSender: @unchecked Sendable {
    var onSend: (@Sendable (Data, Bool) -> Void)?
    var connected = false { didSet { attempt() } }
    var suspended = false { didSet { attempt() } }
    var consoleTakesInput: Bool? { didSet { attempt() } }
    var padHidden = false { didSet { attempt() } }
    private(set) var sentCount = 0

    private var transmission = PadTransmission()
    private let timer: DispatchSourceTimer

    init(queue: DispatchQueue) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        self.timer = timer
        timer.setEventHandler { [weak self] in self?.attempt() }
        timer.resume()
    }

    deinit {
        timer.cancel()
    }

    func setState(_ new: PadState) {
        emit(transmission.update(new, now: MonotonicClock.now()))
    }

    private var active: Bool {
        connected && !suspended && consoleTakesInput == true && !padHidden
    }

    private func attempt() {
        let now = MonotonicClock.now()
        emit(transmission.setActive(active, now: now))
        emit(transmission.heartbeat(now: now))
    }

    private func emit(_ message: PadTransmission.Message?) {
        guard let message else { return }
        onSend?(message.data, message.droppable)
        sentCount += 1
    }
}

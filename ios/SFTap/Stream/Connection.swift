// SPDX-License-Identifier: GPL-2.0-only
import Foundation
import Network
import SFTCore

final class Connection: @unchecked Sendable {
    enum Failure {
        case timeout
        case refused
        case idle
        case closed
        case `protocol`(String)
        case network(String)

        var reason: String {
            switch self {
            case .timeout:
                return "连不上：检查 Tailscale 是否开启、地址是否正确，或是否已有其他播放器连着 Switch（同一时间只能一个）"
            case .refused:
                return "Switch 没有在网络模式下串流：在 Switch 上把 Connection 设为 Network 并重启"
            case .idle:
                return "超过 5 秒没有收到数据，正在重连"
            case .closed:
                return "Switch 断开了连接"
            case .protocol(let detail):
                return "数据格式错误：\(detail)"
            case .network(let detail):
                return "网络错误：\(detail)"
            }
        }
    }

    var onReady: (() -> Void)?
    var onPackets: (([Packet]) -> Void)?
    var onInputCapability: ((Bool) -> Void)?
    var onFail: ((Failure) -> Void)?

    private let queue: DispatchQueue
    private let conn: NWConnection
    private var reader = PacketReader()
    private var readyTimer: DispatchSourceTimer?
    private var watchdog: DispatchSourceTimer?
    private var lastBytesAt: TimeInterval
    private var inFlight = 0
    private var finished = false
    private(set) var bytesReceived = 0

    init(host: String, port: Int, queue: DispatchQueue) {
        self.queue = queue
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 5
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        tcp.keepaliveInterval = 1
        tcp.keepaliveCount = 3
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? .any
        )
        conn = NWConnection(to: endpoint, using: NWParameters(tls: nil, tcp: tcp))
        lastBytesAt = MonotonicClock.now()
    }

    func start() {
        reader.onInputCapability = { [weak self] takes in
            self?.onInputCapability?(takes)
        }
        conn.stateUpdateHandler = { [weak self] state in
            self?.stateChanged(state)
        }
        conn.start(queue: queue)
        let ready = DispatchSource.makeTimerSource(queue: queue)
        ready.schedule(deadline: .now() + 5)
        ready.setEventHandler { [weak self] in
            self?.fail(.timeout)
        }
        ready.resume()
        readyTimer = ready
        let watch = DispatchSource.makeTimerSource(queue: queue)
        watch.schedule(deadline: .now() + 1, repeating: 1)
        watch.setEventHandler { [weak self] in
            guard let self, MonotonicClock.now() - self.lastBytesAt > 5 else { return }
            self.fail(.idle)
        }
        watch.resume()
        watchdog = watch
        receive()
    }

    func send(_ data: Data, droppable: Bool = false) {
        guard !finished else { return }
        if droppable && inFlight > 4 { return }
        inFlight += 1
        conn.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.inFlight -= 1
        })
    }

    func close() {
        guard !finished else { return }
        conn.send(content: nil, contentContext: .finalMessage, isComplete: true,
                  completion: .contentProcessed { [weak self] _ in self?.cancel() })
        queue.asyncAfter(deadline: .now() + 0.2) { [self] in cancel() }
    }

    func cancel() {
        finished = true
        readyTimer?.cancel()
        watchdog?.cancel()
        onReady = nil
        onPackets = nil
        onInputCapability = nil
        onFail = nil
        reader.onInputCapability = nil
        conn.cancel()
    }

    private func stateChanged(_ state: NWConnection.State) {
        guard !finished else { return }
        switch state {
        case .ready:
            readyTimer?.cancel()
            onReady?()
        case .waiting(let error):
            if case .posix(let code) = error, code == .ECONNREFUSED {
                fail(.refused)
            }
        case .failed(let error):
            failNetwork(error)
        case .cancelled:
            finished = true
        default:
            break
        }
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] content, _, complete, error in
            guard let self, !self.finished else { return }
            if let error {
                self.failNetwork(error)
                return
            }
            if let content, !content.isEmpty {
                self.lastBytesAt = MonotonicClock.now()
                self.bytesReceived += content.count
                do {
                    let packets = try self.reader.feed(content)
                    if !packets.isEmpty { self.onPackets?(packets) }
                } catch {
                    self.fail(.protocol("\(error)"))
                    return
                }
            }
            if complete {
                self.fail(.closed)
                return
            }
            self.receive()
        }
    }

    private func fail(_ failure: Failure) {
        guard !finished else { return }
        let callback = onFail
        cancel()
        callback?(failure)
    }

    private func failNetwork(_ error: NWError) {
        if case .posix(let code) = error, code == .ECONNREFUSED {
            fail(.refused)
        } else if case .posix(let code) = error, code == .ETIMEDOUT {
            fail(.timeout)
        } else {
            fail(.network(error.localizedDescription))
        }
    }
}

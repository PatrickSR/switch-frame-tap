// SPDX-License-Identifier: GPL-2.0-only
import Foundation

public enum SFTRError: Error, Equatable {
    case truncatedHeader
    case badMagic
    case unsupportedVersion(UInt16)
    case unsupportedFlags(UInt16)
    case invalidStatusPacket
    case invalidAudioPacket
    case invalidVideoPacket
}

public struct SFTRHeader: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case video
        case audio
        case status
    }

    public static let size = 32
    public static let videoFlag: UInt16 = 2
    public static let keyFlag: UInt16 = 4
    public static let audioFlag: UInt16 = 8
    public static let statusFlag: UInt16 = 16
    public static let cropFlag: UInt16 = 32
    public static let cropMidFlag: UInt16 = 64
    public static let inputFlag: UInt16 = 128
    public static let maxVideoPayload: UInt32 = 8 * 1024 * 1024
    public static let maxAudioPayload: UInt32 = 65536
    public static let maxStatusPayload: UInt32 = 4096

    public let rawFlags: UInt16
    public let flags: UInt16
    public let width: UInt32
    public let height: UInt32
    public let consoleAgeMicros: UInt32
    public let payloadLength: UInt32
    public let crop: UInt32
    public let sequence: UInt32

    public init(_ data: Data) throws {
        guard data.count >= Self.size else { throw SFTRError.truncatedHeader }
        guard Self.u32(data, at: 0) == 0x5254_4653 else { throw SFTRError.badMagic }
        let version = Self.u16(data, at: 4)
        guard version == 2 else { throw SFTRError.unsupportedVersion(version) }
        rawFlags = Self.u16(data, at: 6)
        flags = rawFlags & ~Self.inputFlag
        width = Self.u32(data, at: 8)
        height = Self.u32(data, at: 12)
        consoleAgeMicros = Self.u32(data, at: 16)
        payloadLength = Self.u32(data, at: 20)
        crop = Self.u32(data, at: 24)
        sequence = Self.u32(data, at: 28)
    }

    public var consoleTakesInput: Bool? {
        if rawFlags & Self.audioFlag != 0 && rawFlags & Self.statusFlag == 0 { return nil }
        return rawFlags & Self.inputFlag != 0
    }

    public var isEmptyKeepalive: Bool { flags == 0 && payloadLength == 0 }
    public var isStatus: Bool { flags & Self.statusFlag != 0 }
    public var isAudio: Bool { flags & Self.audioFlag != 0 && flags & Self.statusFlag == 0 }
    public var isVideo: Bool { !isStatus && !isAudio }
    public var isKeyFrame: Bool { flags & Self.keyFlag != 0 }
    public var kind: Kind { isStatus ? .status : (isAudio ? .audio : .video) }

    public func validate() throws {
        if flags & ~(Self.videoFlag | Self.keyFlag | Self.audioFlag | Self.statusFlag | Self.cropFlag | Self.cropMidFlag) != 0 {
            throw SFTRError.unsupportedFlags(flags)
        }
        if isStatus {
            guard flags == Self.audioFlag | Self.statusFlag,
                  payloadLength >= 8, payloadLength <= Self.maxStatusPayload
            else { throw SFTRError.invalidStatusPacket }
            return
        }
        if isAudio {
            guard flags == Self.audioFlag,
                  width == 48000, height == 2,
                  payloadLength >= 1, payloadLength <= Self.maxAudioPayload,
                  payloadLength % 4 == 0
            else { throw SFTRError.invalidAudioPacket }
            return
        }
        guard flags & Self.videoFlag != 0,
              width >= 16, width <= 1920, height >= 16, height <= 1088,
              width % 2 == 0, height % 2 == 0,
              payloadLength >= 1, payloadLength <= Self.maxVideoPayload
        else { throw SFTRError.invalidVideoPacket }
    }

    static func u16(_ d: Data, at i: Int) -> UInt16 {
        let s = d.startIndex + i
        return UInt16(d[s]) | UInt16(d[s + 1]) << 8
    }

    static func u32(_ d: Data, at i: Int) -> UInt32 {
        let s = d.startIndex + i
        return UInt32(d[s]) | UInt32(d[s + 1]) << 8 | UInt32(d[s + 2]) << 16 | UInt32(d[s + 3]) << 24
    }
}

public struct Packet: Sendable {
    public let header: SFTRHeader
    public let payload: Data
    public let receivedAt: TimeInterval

    public init(header: SFTRHeader, payload: Data, receivedAt: TimeInterval) {
        self.header = header
        self.payload = payload
        self.receivedAt = receivedAt
    }

    public var kind: SFTRHeader.Kind { header.kind }
    public var sequence: UInt32 { header.sequence }
    public var consoleAgeMicros: UInt32 { header.consoleAgeMicros }
    public var width: UInt32 { header.width }
    public var height: UInt32 { header.height }
    public var isVideo: Bool { header.isVideo }
    public var isAudio: Bool { header.isAudio }
    public var isStatus: Bool { header.isStatus }
    public var isKeyFrame: Bool { header.isKeyFrame }
}

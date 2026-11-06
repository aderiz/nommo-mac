import Foundation

public struct RGB: Codable, Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(255, 255, 255)

    /// Scales every channel by `factor` (clamped to 0...1).
    public func scaled(by factor: Double) -> RGB {
        let f = min(max(factor, 0), 1)
        return RGB(UInt8((Double(r) * f).rounded()), UInt8((Double(g) * f).rounded()), UInt8((Double(b) * f).rounded()))
    }

    /// Linear blend towards `other` by `t` (0...1).
    public func mixed(with other: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        func lerp(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded()) }
        return RGB(lerp(r, other.r), lerp(g, other.g), lerp(b, other.b))
    }
}

/// High-level control of the speaker, mirroring the command sequences Synapse (Windows) sends.
///
/// Deliberately has no API for the audio-source command (class 0x08 command 0x0A): it can switch the
/// speaker to Bluetooth, which drops the USB control channel until someone presses a physical button.
public actor NommoDevice {
    private let transport: any HIDTransport
    private var nextTransaction: UInt8 = 0
    private var softwareLightingActive = false

    public init(transport: any HIDTransport) {
        self.transport = transport
    }

    // MARK: - Low level

    private func takeTransaction() -> UInt8 {
        defer { nextTransaction = (nextTransaction + 1) & 0x1F }
        return nextTransaction
    }

    /// Sends a command. When `waitForStatus` is true, polls until the speaker reports OK (like Synapse does).
    @discardableResult
    func send(
        _ commandClass: UInt8, _ commandID: UInt8, _ arguments: [UInt8],
        waitForStatus: Bool = true, timeout: TimeInterval = 1.0
    ) async throws -> [UInt8] {
        let packet = RazerPacket(
            transactionID: takeTransaction(), commandClass: commandClass,
            commandID: commandID, arguments: arguments
        )
        try transport.setFeature(packet.encoded())
        guard waitForStatus else { return [] }
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            try await Task.sleep(for: .milliseconds(10))
            let reply = try transport.getFeature()
            if reply.count >= NommoProtocol.reportLength, reply[1] == RazerPacket.Status.ok {
                return Array(reply[9 ..< 89])
            }
            if Date() > deadline { throw NommoError.notReady }
        }
    }

    /// Reads a value: sends the getter and returns the 80-byte data area.
    func query(_ commandClass: UInt8, _ commandID: UInt8, _ arguments: [UInt8] = []) async throws -> [UInt8] {
        try await send(commandClass, commandID, arguments)
    }

    // MARK: - Identity

    public func serialNumber() async throws -> String {
        let data = try await query(0x00, 0x82)
        let bytes = data.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Lighting

    /// Switches the speaker into software lighting mode so it accepts streamed frames.
    public func beginSoftwareLighting() async throws {
        try await send(0x00, 0x84, [0, 0])
        try await send(0x00, 0x04, [3, 0])             // device mode 3 = software
        try await send(0x0F, 0x02, [0, 0, 8, 0, 0, 0]) // effect 8 = custom frames
        softwareLightingActive = true
    }

    public var isSoftwareLightingActive: Bool { softwareLightingActive }

    /// Marks lighting as released. Stopping the frame stream is what hands control back to the speaker's
    /// own colour cycle, so no command is needed.
    public func endSoftwareLighting() {
        softwareLightingActive = false
    }

    /// Streams one frame. `right` drives LEDs 0-5 and `left` drives LEDs 6-11.
    public func sendFrame(left: RGB, right: RGB) async throws {
        var args: [UInt8] = [0, 0, 0, 0, UInt8(NommoProtocol.ledCount - 1)]
        for _ in 0 ..< 6 { args += [right.r, right.g, right.b] }
        for _ in 0 ..< 6 { args += [left.r, left.g, left.b] }
        try await send(0x0F, 0x03, args, waitForStatus: false)
    }

    public func setBrightness(_ level: UInt8) async throws {
        try await send(0x0F, 0x04, [1, 0, level])
    }

    public func brightness() async throws -> UInt8 {
        try await query(0x0F, 0x84, [1, 0, 0])[2]
    }

    // MARK: - Audio

    public func setEQPreset(_ preset: EQPreset) async throws {
        try await send(0x08, 0x02, [1, preset.rawValue])
    }

    /// The preset the speaker reports as active (`08/82`). Custom reads back as 0x10.
    public func eqPreset() async throws -> EQPreset? {
        let data = try await query(0x08, 0x82)
        switch data[1] {
        case 1: return .game
        case 2: return .music
        case 3: return .movie
        case 4, 0x10: return .custom
        default: return nil
        }
    }

    /// Writes the ten band gains to the speaker. Raw device values: 0x0C is flat.
    public func setEQBands(_ rawValues: [UInt8]) async throws {
        precondition(rawValues.count == EQ.bandCount)
        try await send(0x08, 0x04, [0] + rawValues)
    }

    public func eqBands() async throws -> [UInt8] {
        let data = try await query(0x08, 0x84)
        return Array(data[1 ... EQ.bandCount])
    }
}

import Foundation

/// Constants for the Razer Nommo V2 Pro (USB 1532:055A).
public enum NommoProtocol {
    public static let vendorID = 0x1532
    public static let productID = 0x055A
    /// HID feature report that carries Razer's 90-byte command packets.
    public static let reportID: UInt8 = 7
    /// Report ID byte + 90-byte packet.
    public static let reportLength = 91
    /// Lighting frames address 12 LEDs: 0-5 are the right speaker, 6-11 the left.
    public static let ledCount = 12
}

/// One Razer command packet, as sent in feature report 7.
///
/// Layout of the 91-byte report (observed in Synapse's traffic):
/// `[0]=report id (7) [1]=status [2]=txn [3..4]=remaining [5]=protocol [6]=arg size
///  [7]=class [8]=command [9...]=arguments ... [89]=crc (xor of bytes 3...88)`
public struct RazerPacket: Equatable, Sendable {
    public var status: UInt8
    public var transactionID: UInt8
    public var commandClass: UInt8
    public var commandID: UInt8
    public var arguments: [UInt8]

    public init(
        status: UInt8 = 0,
        transactionID: UInt8,
        commandClass: UInt8,
        commandID: UInt8,
        arguments: [UInt8] = []
    ) {
        self.status = status
        self.transactionID = transactionID
        self.commandClass = commandClass
        self.commandID = commandID
        self.arguments = arguments
    }

    /// Largest argument block that fits (bytes 9 through 88).
    public static let maxArguments = 80

    public func encoded() -> [UInt8] {
        precondition(arguments.count <= Self.maxArguments, "argument block too large")
        var f = [UInt8](repeating: 0, count: NommoProtocol.reportLength)
        f[0] = NommoProtocol.reportID
        f[1] = status
        f[2] = transactionID
        f[6] = UInt8(arguments.count)
        f[7] = commandClass
        f[8] = commandID
        for (i, byte) in arguments.enumerated() { f[9 + i] = byte }
        f[89] = Self.checksum(f)
        return f
    }

    /// XOR of bytes 3...88.
    static func checksum(_ f: [UInt8]) -> UInt8 {
        f[3...88].reduce(0, ^)
    }

    /// Parses a report read back from the device. Returns nil if it is the wrong shape.
    public static func decode(_ bytes: [UInt8]) -> RazerPacket? {
        guard bytes.count >= NommoProtocol.reportLength, bytes[0] == NommoProtocol.reportID else { return nil }
        let size = Int(bytes[6])
        guard size <= maxArguments else { return nil }
        return RazerPacket(
            status: bytes[1],
            transactionID: bytes[2],
            commandClass: bytes[7],
            commandID: bytes[8],
            arguments: Array(bytes[9 ..< 9 + size])
        )
    }

    /// Status values the speaker returns after a command.
    public enum Status {
        public static let busy: UInt8 = 1
        public static let ok: UInt8 = 2
    }
}

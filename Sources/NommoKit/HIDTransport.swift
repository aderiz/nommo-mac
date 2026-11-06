import Foundation
import IOKit.hid

public enum NommoError: Error, Equatable {
    case deviceNotFound
    case openFailed(Int32)
    case ioFailed(Int32)
    case notReady
    case malformedReply
}

/// Minimal abstraction over feature-report I/O so the protocol layer can be tested without hardware.
public protocol HIDTransport: Sendable {
    /// Sends a full 91-byte report (first byte = report id).
    func setFeature(_ report: [UInt8]) throws
    /// Reads feature report 7 and returns the full 91 bytes (first byte = report id).
    func getFeature() throws -> [UInt8]
}

/// IOKit-backed transport for the Nommo V2 Pro's single HID interface.
public final class IOKitHIDTransport: HIDTransport, @unchecked Sendable {
    private let device: IOHIDDevice

    private init(device: IOHIDDevice) {
        self.device = device
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// True if a Nommo V2 Pro is currently attached (does not open it).
    public static func isDevicePresent() -> Bool {
        findDevice() != nil
    }

    /// Opens the first attached Nommo V2 Pro.
    public static func open() throws -> IOKitHIDTransport {
        guard let device = findDevice() else { throw NommoError.deviceNotFound }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw NommoError.openFailed(result) }
        return IOKitHIDTransport(device: device)
    }

    private static func findDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: NommoProtocol.vendorID,
            kIOHIDProductIDKey as String: NommoProtocol.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager), let first = (set as NSSet).allObjects.first else {
            return nil
        }
        return (first as! IOHIDDevice) // swiftlint:disable:this force_cast
    }

    public func setFeature(_ report: [UInt8]) throws {
        let result = report.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(
                device, kIOHIDReportTypeFeature,
                CFIndex(NommoProtocol.reportID), buf.baseAddress!, buf.count
            )
        }
        guard result == kIOReturnSuccess else { throw NommoError.ioFailed(result) }
    }

    public func getFeature() throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: NommoProtocol.reportLength)
        buffer[0] = NommoProtocol.reportID
        var length = CFIndex(buffer.count)
        let result = buffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceGetReport(
                device, kIOHIDReportTypeFeature,
                CFIndex(NommoProtocol.reportID), buf.baseAddress!, &length
            )
        }
        guard result == kIOReturnSuccess else { throw NommoError.ioFailed(result) }
        return Array(buffer.prefix(Int(length)))
    }
}

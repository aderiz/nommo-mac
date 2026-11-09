import Foundation

// Reads a small copy of the screen and works out what colour each speaker should show.
//
// A speaker beside the screen should look like a continuation of the picture just past its nearest edge, so each
// side is a weighted average of the picture with the weight falling off away from that side. A small weight is kept
// in the middle so a bright core in the centre of the frame still lights both speakers. Averaging happens in linear
// light, which makes bright regions count for more than dark ones: a white-hot core wins over an amber fringe, the
// way it does to the eye.

// MARK: - Colour

/// sRGB transfer functions.
enum SRGB {
    static let decodeTable: [Float] = (0 ... 255).map { v in
        let c = Float(v) / 255
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    static func encode(_ linear: Float) -> Float {
        let c = min(max(linear, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055
    }
}

/// A colour in linear light, each channel 0...1.
public struct LinearColor: Equatable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float

    public init(_ r: Float, _ g: Float, _ b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let zero = LinearColor(0, 0, 0)

    /// The brightest channel.
    public var peak: Float { max(r, g, b) }
    public var luminance: Float { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// The 8-bit sRGB colour that displays as this.
    public var rgb: RGB {
        func byte(_ v: Float) -> UInt8 { UInt8((SRGB.encode(v) * 255).rounded()) }
        return RGB(byte(r), byte(g), byte(b))
    }
}

// MARK: - Picture bars

/// Black bars around the picture (letterbox above and below, pillarbox at the sides), as fractions of the frame.
public struct Bars: Equatable, Sendable {
    public var top: Float
    public var bottom: Float
    public var leading: Float
    public var trailing: Float

    public init(top: Float = 0, bottom: Float = 0, leading: Float = 0, trailing: Float = 0) {
        self.top = top
        self.bottom = bottom
        self.leading = leading
        self.trailing = trailing
    }

    public static let none = Bars()
}

/// What the screen looks like right now, from the speakers' point of view.
public struct SceneSample: Equatable, Sendable {
    public var left: LinearColor
    public var right: LinearColor
    /// The bars that were excluded from the average.
    public var bars: Bars
    /// The whole frame is black: protected video that capture cannot see, or a genuine black frame.
    public var isBlank: Bool

    public init(left: LinearColor, right: LinearColor, bars: Bars = .none, isBlank: Bool = false) {
        self.left = left
        self.right = right
        self.bars = bars
        self.isBlank = isBlank
    }
}

// MARK: - Reader

/// Turns BGRA frames into `SceneSample`s. Keeps a short history so the picture bars are stable: a subtitle in the
/// bottom bar, or a dark scene, does not make the picture area jump around.
public struct SceneReader: Sendable {
    /// How quickly a side's weight falls away from its edge, as a fraction of the picture width.
    public var edgeFalloff: Float = 0.20
    /// Weight kept everywhere, relative to 1 at the edge, so a bright centre still reaches both speakers.
    public var centreWeight: Float = 0.10
    /// A pixel with every channel at or below this counts as black.
    public var blackLevel: UInt8 = 4
    /// A row or column is a bar when at least this share of it is black.
    public var barShare: Float = 0.88
    /// The frame counts as blank when at least this share of it is black.
    public var blankShare: Float = 0.985

    private var history: [Bars] = []
    private let historyLimit = 60
    private var tracked = Bars.none
    private var weights: (width: Int, left: [Float], right: [Float])?

    public init() {}

    /// Convenience for tests and tools: tightly packed BGRA bytes.
    public mutating func read(bgra bytes: [UInt8], width: Int, height: Int) -> SceneSample {
        bytes.withUnsafeBytes { read(bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4) }
    }

    public mutating func read(bgra base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) -> SceneSample {
        precondition(width > 0 && height > 0)
        let px = base.assumingMemoryBound(to: UInt8.self)
        let black = blackLevel

        @inline(__always) func isBlack(_ p: UnsafePointer<UInt8>) -> Bool { p[0] <= black && p[1] <= black && p[2] <= black }

        // Pass 1: which rows are black.
        var rowBlack = [Int](repeating: 0, count: height)
        var blackTotal = 0
        for y in 0 ..< height {
            let row = px + y * bytesPerRow
            var n = 0
            for x in 0 ..< width where isBlack(row + x * 4) { n += 1 }
            rowBlack[y] = n
            blackTotal += n
        }
        let isBlank = Float(blackTotal) >= blankShare * Float(width * height)

        // Bars. A frame that is almost entirely bar says nothing about where the picture is, so it is ignored.
        var detected: Bars?
        let rowLimit = Int((barShare * Float(width)).rounded(.up))
        var top = 0
        while top < height, rowBlack[top] >= rowLimit { top += 1 }
        var bottom = 0
        while bottom < height - top, rowBlack[height - 1 - bottom] >= rowLimit { bottom += 1 }
        if height - top - bottom >= 4, !isBlank {
            let rows = height - top - bottom
            var colBlack = [Int](repeating: 0, count: width)
            for y in top ..< (height - bottom) {
                let row = px + y * bytesPerRow
                for x in 0 ..< width where isBlack(row + x * 4) { colBlack[x] += 1 }
            }
            let colLimit = Int((barShare * Float(rows)).rounded(.up))
            var leading = 0
            while leading < width, colBlack[leading] >= colLimit { leading += 1 }
            var trailing = 0
            while trailing < width - leading, colBlack[width - 1 - trailing] >= colLimit { trailing += 1 }
            if width - leading - trailing >= 4 {
                detected = Bars(
                    top: Float(top) / Float(height), bottom: Float(bottom) / Float(height),
                    leading: Float(leading) / Float(width), trailing: Float(trailing) / Float(width)
                )
            }
        }
        if let detected { track(detected) }

        // Pass 2: weighted average of the picture area, in linear light.
        var x0 = Int((tracked.leading * Float(width)).rounded())
        var x1 = width - Int((tracked.trailing * Float(width)).rounded())
        var y0 = Int((tracked.top * Float(height)).rounded())
        var y1 = height - Int((tracked.bottom * Float(height)).rounded())
        if x1 - x0 < 2 || y1 - y0 < 2 { (x0, x1, y0, y1) = (0, width, 0, height) }
        let cw = x1 - x0
        let (wl, wr) = edgeWeights(width: cw)

        var l = SIMD3<Float>(repeating: 0), r = SIMD3<Float>(repeating: 0)
        let table = SRGB.decodeTable
        for x in x0 ..< x1 {
            var column = SIMD3<Float>(repeating: 0)
            for y in y0 ..< y1 {
                let p = px + y * bytesPerRow + x * 4
                column += SIMD3(table[Int(p[2])], table[Int(p[1])], table[Int(p[0])])
            }
            l += column * wl[x - x0]
            r += column * wr[x - x0]
        }
        let rows = Float(y1 - y0)
        let nl = rows * wl.reduce(0, +), nr = rows * wr.reduce(0, +)
        let left = l / nl, right = r / nr
        return SceneSample(
            left: LinearColor(left.x, left.y, left.z), right: LinearColor(right.x, right.y, right.z),
            bars: tracked, isBlank: isBlank
        )
    }

    private mutating func track(_ bars: Bars) {
        history.append(bars)
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
        func median(_ key: KeyPath<Bars, Float>) -> Float {
            let sorted = history.map { $0[keyPath: key] }.sorted()
            return sorted[sorted.count / 2]
        }
        tracked = Bars(top: median(\.top), bottom: median(\.bottom), leading: median(\.leading), trailing: median(\.trailing))
    }

    private mutating func edgeWeights(width: Int) -> ([Float], [Float]) {
        if let w = weights, w.width == width { return (w.left, w.right) }
        var left = [Float](repeating: 0, count: width), right = left
        for i in 0 ..< width {
            let u = (Float(i) + 0.5) / Float(width)
            left[i] = expf(-u / edgeFalloff) + centreWeight
            right[i] = expf(-(1 - u) / edgeFalloff) + centreWeight
        }
        weights = (width, left, right)
        return (left, right)
    }
}

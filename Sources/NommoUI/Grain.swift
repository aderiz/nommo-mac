import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Fine monochrome film grain. Wide, slow gradients show visible bands on their own; a little noise breaks
/// the bands up and gives the surface some texture.
struct Grain: View {
    var opacity: Double = 0.13

    private static let image: CGImage? = {
        let noise = CIFilter.randomGenerator().outputImage
        let mono = noise?.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.4])
        let context = CIContext()
        return mono.flatMap { context.createCGImage($0, from: CGRect(x: 0, y: 0, width: 256, height: 256)) }
    }()

    var body: some View {
        if let image = Self.image {
            Image(decorative: image, scale: 2)
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }
}

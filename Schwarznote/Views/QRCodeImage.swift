//
//  QRCodeImage.swift
//  Schwarznote
//

import CoreImage.CIFilterBuiltins
import SwiftUI

/// Renders a string as a crisp QR code.
struct QRCodeImage: View {
    let content: String

    var body: some View {
        if let image = Self.makeImage(from: content) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private static let context = CIContext()

    private static func makeImage(from string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return context.createCGImage(scaled, from: scaled.extent)
    }
}

#Preview {
    QRCodeImage(content: "https://www.xiaohongshu.com")
        .frame(width: 400, height: 400)
}

// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileCutoutTests.swift
//  claudeBlastTests
//
//  Art lifted off its white ground: what the cut takes, and what it leaves.
//

import Testing
import Foundation
import UIKit
@testable import claudeBlast

extension SerialTests {
@Suite(.serialized)
struct TileCutoutTests {

    /// 100×100 white paper with a black ring (white inside) and a black square:
    /// the ring's inside is enclosed white, which looks exactly like a pillow.
    private func ringPicture() -> CGImage {
        let size = CGSize(width: 100, height: 100)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 50, height: 50))
            ring.lineWidth = 6
            ring.stroke()
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 70, y: 70, width: 20, height: 20))
        }.cgImage!
    }

    /// Alpha at a pixel, top-left origin.
    private func alpha(_ image: CGImage, _ x: Int, _ y: Int) -> UInt8 {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return px[3]
    }

    @Test("The edge cut clears the paper and keeps enclosed white")
    func edgeCutKeepsEnclosedWhite() throws {
        let result = try #require(TileCutout.cut(ringPicture()))
        #expect(alpha(result.image, 2, 2) == 0)        // paper at the corner
        #expect(alpha(result.image, 95, 50) == 0)      // paper beside the square
        #expect(alpha(result.image, 35, 35) == 255)    // inside the ring: kept
        #expect(alpha(result.image, 80, 80) == 255)    // the square itself
        #expect(result.holesCut == 0)
    }

    @Test("A reviewed hole point clears that enclosed region only")
    func holePointClearsItsRegion() throws {
        var options = TileCutout.Options()
        options.holes = [CGPoint(x: 0.35, y: 0.35)]
        let result = try #require(TileCutout.cut(ringPicture(), options: options))
        #expect(alpha(result.image, 35, 35) == 0)
        #expect(alpha(result.image, 80, 80) == 255)
        #expect(result.holesCut == 1)
    }

    @Test("A hole point that lands on the picture cuts nothing")
    func holePointOnInkCutsNothing() throws {
        var options = TileCutout.Options()
        options.holes = [CGPoint(x: 0.8, y: 0.8)]
        let result = try #require(TileCutout.cut(ringPicture(), options: options))
        #expect(result.holesCut == 0)
        #expect(alpha(result.image, 80, 80) == 255)
    }

    @Test("Cut art reads as transparent; the white master does not")
    func transparencyIsDetected() throws {
        let master = ringPicture()
        let result = try #require(TileCutout.cut(master))
        #expect(!TileCutout.hasTransparency(master))
        #expect(TileCutout.hasTransparency(result.image))
    }

    /// Playful 3D's clay has no outlines, so a cream egg on white has nowhere
    /// for the cut to stop; High Contrast is white on black. Neither is cut.
    @Test("Only Classic and its tones are cut")
    func onlyClassicFamilyCuts() {
        #expect(ImageSetID.classic.cutsArt)
        #expect(ImageSetID.classicMedium.cutsArt)
        #expect(ImageSetID.classicMediumDark.cutsArt)
        #expect(!ImageSetID.playful3D.cutsArt)
        #expect(!ImageSetID.highContrast.cutsArt)
    }

    @Test("Generated art for an uncut set is stored opaque")
    func uncutSetStoresOpaque() throws {
        let data = try TilePhotoProcessor.processArt(UIImage(cgImage: ringPicture()), for: .playful3D)
        let image = try #require(UIImage(data: data)?.cgImage)
        #expect(!TileCutout.hasTransparency(image))
    }
}
}

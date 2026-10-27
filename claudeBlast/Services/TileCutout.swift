// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileCutout.swift
//  claudeBlast
//
//  Lift tile art off its white ground, so the tile's own colour shows through.
//

import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Removes the white ground from a picture drawn on white.
///
/// ## Why this exists
///
/// Tiles draw their art straight on a light Fitzgerald tint, so the art needs a
/// transparent background. Every picture we have — and every one gpt-image-2
/// will make, since it refuses `background: transparent` — is drawn on white.
/// The colour cannot be baked in instead: it comes from each child's palette.
///
/// ## How
///
/// 1. **The edge cut.** Near-white pixels connected to the border are ground.
///    Classic's black outlines stop the fill, so the white of an eye, a plate
///    or a sheep's wool stays. This is always safe, and it is all the app does
///    to art it generates.
/// 2. **Holes, only where someone said so.** Ground trapped inside a picture —
///    the inside of a cup handle, a donut's hole, the gap between an arm and a
///    hip — is indistinguishable, pixel for pixel, from a white part of the
///    picture: Classic paints a pillow the same white as the paper. So a hole
///    is cut only at a point listed for that tile (`Options.holes`), recorded
///    once a person has looked. `proposeHoles` suggests them, from Vision's
///    subject mask, for that person to confirm; it is never trusted alone,
///    because it calls every white area background, pillows and sails included.
/// 3. **Clean edges.** The anti-aliased rim of an outline is part white. Pixels
///    next to the cut are un-blended from white ("colour to alpha"), so no white
///    fringe shows on a coloured tile.
///
/// Compiled into the app (for art generated on the device) and into
/// `tools/cutout` (for the shipped sets), so both cut the same way.
enum TileCutout {

    struct Options {
        /// A pixel is ground-coloured when its darkest channel is at least this.
        var whiteThreshold: UInt8 = 232
        /// Enclosed ground to cut, as points inside each region, in unit
        /// coordinates from the top-left. A point that lands on the picture
        /// rather than on enclosed ground cuts nothing.
        var holes: [CGPoint] = []
        /// Clear every near-white pixel, enclosed or not. For code-drawn word
        /// tiles, where the counters of "a" and "e" are holes, not paper.
        var clearAllWhite = false
    }

    struct Result {
        let image: CGImage
        /// Listed holes that landed on enclosed ground and were cut.
        let holesCut: Int
        /// Share of the picture that became transparent.
        let clearedFraction: Double
    }

    /// Enclosed regions smaller than this share of the picture are not offered
    /// as holes. Measured on Classic (2026-10-26): eye whites, teeth and the
    /// like are 0.03–0.25% of a tile; the smallest real holes (the arm on the
    /// hip in `can`, a bag's handle) are about 0.5%.
    private static let minHoleFraction = 0.0035

    /// `edgeOnSubject` above this, and the edge cut is taking part of the
    /// picture. Measured on Classic (2026-10-26): clean tiles sit at 0–0.2%
    /// (outline rims); the doctor's coat that ran into the paper was 0.9%, the
    /// dentist's 5%. Matches `EDGE_GUARD` in `tools/cutout_review.py`.
    static let edgeGuard = 0.002

    // MARK: - Regions

    /// The picture in RGBA, and its near-white ground labelled into regions.
    private struct Ground {
        let ctx: CGContext
        let px: UnsafeMutablePointer<UInt8>
        let w: Int, h: Int
        var label: [Int32]
        var touchesEdge: [Bool]
        var size: [Int]
        var count: Int { size.count - 1 }

        init?(_ image: CGImage, threshold: UInt8) {
            w = image.width; h = image.height
            let n = w * h
            guard n > 0, let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let base = ctx.data else { return nil }
            // Paint white first, so art that already has transparent areas is
            // treated as drawn on white rather than on black.
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            self.ctx = ctx
            px = base.bindMemory(to: UInt8.self, capacity: n * 4)

            var ground = [Bool](repeating: false, count: n)
            for i in 0..<n {
                let o = i * 4
                ground[i] = min(px[o], px[o + 1], px[o + 2]) >= threshold
            }
            label = [Int32](repeating: 0, count: n)
            touchesEdge = [false]
            size = [0]
            var stack: [Int] = []
            var next: Int32 = 0
            for start in 0..<n where ground[start] && label[start] == 0 {
                next += 1
                var edge = false, count = 0
                label[start] = next
                stack.append(start)
                while let i = stack.popLast() {
                    count += 1
                    let x = i % w, y = i / w
                    if x == 0 || y == 0 || x == w - 1 || y == h - 1 { edge = true }
                    if x > 0, ground[i - 1], label[i - 1] == 0 { label[i - 1] = next; stack.append(i - 1) }
                    if x < w - 1, ground[i + 1], label[i + 1] == 0 { label[i + 1] = next; stack.append(i + 1) }
                    if y > 0, ground[i - w], label[i - w] == 0 { label[i - w] = next; stack.append(i - w) }
                    if y < h - 1, ground[i + w], label[i + w] == 0 { label[i + w] = next; stack.append(i + w) }
                }
                touchesEdge.append(edge)
                size.append(count)
            }
        }

        /// The region under a unit-coordinate point, if it is enclosed ground.
        func enclosedRegion(at p: CGPoint) -> Int? {
            let x = min(w - 1, max(0, Int(p.x * CGFloat(w))))
            let y = min(h - 1, max(0, Int(p.y * CGFloat(h))))
            let l = Int(label[y * w + x])
            return l > 0 && !touchesEdge[l] ? l : nil
        }

        /// One point inside region `l`: its pixel nearest the centroid. A
        /// ring's centroid can fall outside the ring, and the point has to land
        /// on the region it names.
        func point(inside l: Int) -> CGPoint {
            var sx = 0.0, sy = 0.0
            let n = w * h
            for i in 0..<n where Int(label[i]) == l { sx += Double(i % w); sy += Double(i / w) }
            let cx = sx / Double(size[l]), cy = sy / Double(size[l])
            var best = 0, bestD = Double.infinity
            for i in 0..<n where Int(label[i]) == l {
                let dx = Double(i % w) - cx, dy = Double(i / w) - cy
                let d = dx * dx + dy * dy
                if d < bestD { bestD = d; best = i }
            }
            return CGPoint(x: (Double(best % w) + 0.5) / Double(w), y: (Double(best / w) + 0.5) / Double(h))
        }
    }

    // MARK: - Cut

    static func cut(_ image: CGImage, options: Options = Options()) -> Result? {
        guard let g = Ground(image, threshold: options.whiteThreshold) else { return nil }
        let w = g.w, h = g.h, n = w * h, px = g.px

        var clear = [Bool](repeating: false, count: g.count + 1)
        for l in stride(from: 1, through: g.count, by: 1) {
            clear[l] = options.clearAllWhite || g.touchesEdge[l]
        }
        var holesCut = 0
        if !options.clearAllWhite {
            for p in options.holes {
                if let l = g.enclosedRegion(at: p), !clear[l] {
                    clear[l] = true
                    holesCut += 1
                }
            }
        }

        // Apply: cleared ground goes transparent; its neighbours are un-blended
        // from white so an outline's soft rim carries no white halo.
        var cleared = 0
        var isClear = [Bool](repeating: false, count: n)
        for i in 0..<n where g.label[i] > 0 && clear[Int(g.label[i])] {
            isClear[i] = true
            cleared += 1
        }
        for i in 0..<n {
            let o = i * 4
            if isClear[i] {
                px[o] = 0; px[o + 1] = 0; px[o + 2] = 0; px[o + 3] = 0
                continue
            }
            let x = i % w, y = i / w
            var nearClear = false
            for dy in -2...2 where !nearClear {
                let yy = y + dy
                guard yy >= 0, yy < h else { continue }
                for dx in -2...2 {
                    let xx = x + dx
                    if xx >= 0, xx < w, isClear[yy * w + xx] { nearClear = true; break }
                }
            }
            guard nearClear else { continue }
            let r = Double(px[o]), gr = Double(px[o + 1]), b = Double(px[o + 2])
            let a = max(255 - r, 255 - gr, 255 - b) / 255
            guard a < 1 else { continue }
            if a <= 0 {
                px[o] = 0; px[o + 1] = 0; px[o + 2] = 0; px[o + 3] = 0
                continue
            }
            // Colour-to-alpha against white, stored premultiplied.
            func channel(_ c: Double) -> UInt8 {
                let straight = (c - (1 - a) * 255) / a
                return UInt8(max(0, min(255, (straight * a).rounded())))
            }
            px[o] = channel(r); px[o + 1] = channel(gr); px[o + 2] = channel(b)
            px[o + 3] = UInt8((a * 255).rounded())
        }

        guard let out = g.ctx.makeImage() else { return nil }
        return Result(image: out, holesCut: holesCut, clearedFraction: Double(cleared) / Double(n))
    }

    // MARK: - Proposals (tools only)

    /// Suggestions for a person to confirm, from Vision's subject mask:
    ///
    /// - `holes`: enclosed white regions Vision leaves out of the subject —
    ///   maybe a cup handle's inside, maybe a pillow. Never a decision on its
    ///   own: Vision excludes white things wholesale, so it proposes the pillow
    ///   and the sail along with the cup handle.
    /// - `edgeOnSubject`: how much of what the edge cut removes Vision counts
    ///   as subject, as a share of the picture. The edge cut is safe while the
    ///   art's outlines are closed. A doctor's coat whose lines stop short of
    ///   the frame flows into the paper, and the edge cut would take it; Vision
    ///   includes the coat in the figure, so a share above noise sends the tile
    ///   to review, where it can be left uncut.
    ///
    /// Nil when Vision is unavailable or finds no subject.
    static func propose(_ image: CGImage, whiteThreshold: UInt8 = 232)
        -> (holes: [CGPoint], edgeOnSubject: Double)? {
        guard let g = Ground(image, threshold: whiteThreshold),
              let subject = subjectMask(for: image, width: g.w, height: g.h) else { return nil }
        let n = g.w * g.h
        let minSize = max(1, Int(Double(n) * minHoleFraction))
        var sum = [Double](repeating: 0, count: g.count + 1)
        var onEdgeCut = 0
        for i in 0..<n where g.label[i] > 0 {
            let l = Int(g.label[i])
            sum[l] += Double(subject[i])
            if g.touchesEdge[l], subject[i] > 0.5 { onEdgeCut += 1 }
        }
        var holes: [CGPoint] = []
        for l in stride(from: 1, through: g.count, by: 1)
        where !g.touchesEdge[l] && g.size[l] >= minSize && sum[l] / Double(g.size[l]) < 0.5 {
            holes.append(g.point(inside: l))
        }
        return (holes, Double(onEdgeCut) / Double(n))
    }

    // MARK: - Transparency

    /// True when the picture already has see-through pixels — it was cut, or
    /// came that way. A picture without them (a photo, art made before cutting)
    /// draws on a framed white plate instead of straight on the tint.
    static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let side = 32
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let base = ctx.data else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let px = base.bindMemory(to: UInt8.self, capacity: side * side * 4)
        // The corners of a drawn-on-white tile are ground; cut ones are clear.
        let corners = [0, side - 1, side * (side - 1), side * side - 1]
        return corners.contains { px[$0 * 4 + 3] < 128 }
    }

    /// Vision's foreground mask at the picture's size, 0 = background, 1 = subject.
    private static func subjectMask(for image: CGImage, width w: Int, height h: Int) -> [Float]? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let buffer = try? observation.generateScaledMaskForImage(
                forInstances: observation.allInstances, from: handler) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetWidth(buffer) == w, CVPixelBufferGetHeight(buffer) == h,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var out = [Float](repeating: 0, count: w * h)
        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_OneComponent32Float:
            for y in 0..<h {
                let row = (base + y * rowBytes).bindMemory(to: Float.self, capacity: w)
                for x in 0..<w { out[y * w + x] = row[x] }
            }
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<h {
                let row = (base + y * rowBytes).bindMemory(to: UInt8.self, capacity: w)
                for x in 0..<w { out[y * w + x] = Float(row[x]) / 255 }
            }
        default:
            return nil
        }
        return out
    }
}

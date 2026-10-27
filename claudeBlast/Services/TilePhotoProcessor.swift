// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TilePhotoProcessor.swift
//  claudeBlast
//
//  Downscale + compress a caregiver-supplied photo into a CloudKit-safe blob
//  for TileModel.userImageData. CloudKit silently stops syncing records that
//  exceed ~1MB, so a tile's photo is hard-capped well under that ceiling.
//
//  The caregiver first picks a 1:1 region in SquareImageCropper (which
//  normalizes orientation up front); this step is the final, orientation-free
//  downscale + compress on that already-square, already-upright crop.
//

import Foundation
import ImageIO
import UIKit

enum TilePhotoProcessor {
    /// Longest-edge cap. Tiles render small; 512px is plenty and matches the
    /// scene-export resize so a photo round-trips through export unchanged.
    static let maxDimension: CGFloat = 512

    /// Encoded-byte budget. TileModel's other fields are a few short strings, so
    /// 400KB keeps the whole record comfortably under CloudKit's ~1MB limit even
    /// accounting for storage overhead.
    static let maxBytes = 400 * 1024

    enum ProcessError: LocalizedError {
        case tooLargeAfterCompression

        var errorDescription: String? {
            switch self {
            case .tooLargeAfterCompression:
                return "This photo is too detailed to store safely. Try a simpler or more cropped image."
            }
        }
    }

    /// Downscale `image` to within `maxDimension`, then JPEG-compress in a
    /// quality loop until the result is ≤ `maxBytes`. Redrawing through a
    /// renderer also bakes in `imageOrientation`, so the stored bytes are
    /// upright regardless of the source EXIF orientation.
    ///
    /// - Throws: `ProcessError.tooLargeAfterCompression` if even the lowest
    ///   quality exceeds the budget (rare at 512px / JPEG).
    static func process(_ image: UIImage) throws -> Data {
        let resized = downscaled(image, maxDimension: maxDimension)
        for quality in [0.8, 0.6, 0.4, 0.2] as [CGFloat] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
        }
        throw ProcessError.tooLargeAfterCompression
    }

    /// Generated art for `set`, cut off its white ground and stored with its
    /// transparency — the same treatment the shipped sets get.
    ///
    /// **Generated art only, never a photo.** A photo of the child's own cup is
    /// a photo; cutting it would guess at what "background" means in a kitchen.
    /// High Contrast is not cut either: its figures are white on black.
    ///
    /// HEIC, not JPEG, because JPEG has no alpha. The resolver decodes either,
    /// and CloudKit stores the bytes as it always did, so a variant written
    /// before this change (an opaque JPEG) still loads, and draws framed.
    ///
    /// No one reviews art made in the app, so the edge guard decides: if the
    /// edge cut would take part of the picture (a white coat drawn without a
    /// closed outline), or Vision can't say, it is stored uncut and draws
    /// framed. Uncut is always safe; a cut coat is not.
    static func processArt(_ image: UIImage, for set: ImageSetID) throws -> Data {
        guard set.cutsArt else { return try process(image) }
        let resized = downscaled(image, maxDimension: maxDimension)
        guard let source = resized.cgImage,
              let found = TileCutout.propose(source), found.edgeOnSubject <= TileCutout.edgeGuard,
              let cut = TileCutout.cut(source)?.image else { return try process(image) }
        for quality in [0.8, 0.6, 0.4] as [CGFloat] {
            if let data = heic(cut, quality: quality), data.count <= maxBytes { return data }
        }
        throw ProcessError.tooLargeAfterCompression
    }

    private static func heic(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.heic" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Resize so the longest edge is ≤ `maxDimension`, preserving aspect ratio.
    /// Returns the original if it already fits. Mirrors SceneExporter's resize.
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

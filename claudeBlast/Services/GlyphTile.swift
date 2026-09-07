// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GlyphTile.swift
//  claudeBlast
//
//  Letters and numbers, drawn rather than generated.
//

import UIKit
import SwiftUI

/// Tiles whose picture *is* a character.
///
/// ## Why these are drawn, not generated
///
/// Every other tile in this app is an OpenAI image, and for a picture of a cow
/// that is the right answer. For the letter A it is the wrong one in every
/// respect: a glyph rendered from a font is exact, free, instant, identical
/// across all five image sets, and sharp at any size — where 37 words × 5 sets
/// of generation is ~185 images, real money, and a guarantee of inconsistent
/// letterforms. It also sidesteps the problem that decides whether a letter tile
/// works at all, which is legibility at tile size.
///
/// The standing preference already pointed here: colors and shapes prefer
/// deterministic code renders over AI, and `render_shapes.py` /
/// `render_color_spheres.py` are the precedent. This is the same argument with
/// no counter-argument left.
///
/// ## Why the keys are namespaced
///
/// `letter_a`, not `a`. A bare single-character key would collide with real
/// vocabulary — `i` is the pronoun, and `a` is a determiner in any board that
/// grows one. `TileModel.key` is a language-neutral concept id, and "the letter
/// A" and "the word a" are different concepts.
enum GlyphTile {

    static let letterPrefix = "letter_"
    static let numberPrefix = "number_"

    /// The character to draw for a glyph tile key, or nil if it is not one.
    ///
    /// Uppercase only, per the AAC convention for early literacy and because a
    /// single form is the largest and clearest thing that fits a cell.
    static func character(for key: String) -> String? {
        if let letter = key.dropPrefix(letterPrefix), letter.count == 1,
           let scalar = letter.unicodeScalars.first,
           CharacterSet.lowercaseLetters.contains(scalar) {
            return letter.uppercased()
        }
        if let number = key.dropPrefix(numberPrefix),
           !number.isEmpty, number.allSatisfy(\.isNumber) {
            return number
        }
        return covers[key]
    }

    static func isGlyphKey(_ key: String) -> Bool { character(for: key) != nil }

    /// Pack covers for the two glyph packs, drawn like their contents.
    ///
    /// Without this the packs are the only ones in the picker with no cover,
    /// which reads as broken rather than as new. Drawing them costs nothing and
    /// keeps the pack's identity honest — a cover made of the thing inside it.
    private static let covers: [String: String] = [
        "packcover_letters": "ABC",
        "packcover_numbers": "123",
    ]

    /// Every letter key, a–z.
    static var letterKeys: [String] {
        (UnicodeScalar("a").value...UnicodeScalar("z").value)
            .compactMap { UnicodeScalar($0).map { "\(letterPrefix)\($0)" } }
    }

    /// Number keys 0–10. Eleven of them — "0 through 10" is not ten.
    static var numberKeys: [String] { (0...10).map { "\(numberPrefix)\($0)" } }

    // MARK: - Drawing

    /// Draw the glyph for `key` at `size` points, or nil if it is not a glyph
    /// tile.
    ///
    /// Ink and paper come from the image set, so High Contrast inverts and the
    /// three Classic skin tones share one rendering — a glyph has no skin tone,
    /// exactly like the non-people art that is already byte-identical across
    /// those three sets.
    ///
    /// Rasterized on demand rather than kept as files. Everything downstream —
    /// the board, the PDF renderer, OBF export, tile-image export — asks
    /// `TileImageResolver` for pixels, so drawing here reaches all of them
    /// without any of them knowing this is not a photograph.
    static func image(for key: String, in imageSet: ImageSetID,
                      size: CGFloat = 512) -> UIImage? {
        guard let text = character(for: key) else { return nil }

        let isInverted = imageSet == ImageSetID.highContrast
        let paper: UIColor = isInverted ? .black : .white
        let ink: UIColor = isInverted ? .white : .black

        let bounds = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: bounds, format: format).image { context in
            paper.setFill()
            context.fill(CGRect(origin: .zero, size: bounds))

            // Fit the glyph to the cell rather than trusting a point size: "W"
            // and "1" have very different widths, and a fixed size would make one
            // of them tiny or clip the other. Measure, then scale to the box.
            let box = bounds.width * 0.66
            let probe = UIFont.systemFont(ofSize: 100, weight: .semibold)
            let probeSize = (text as NSString).size(withAttributes: [.font: probe])
            let scale = min(box / probeSize.width, box / probeSize.height)
            let font = UIFont.systemFont(ofSize: 100 * scale, weight: .semibold)

            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let drawn = (text as NSString).size(withAttributes: attributes)
            let origin = CGPoint(x: (bounds.width - drawn.width) / 2,
                                 y: (bounds.height - drawn.height) / 2)
            (text as NSString).draw(at: origin, withAttributes: attributes)
        }
    }
}

private extension String {
    /// The remainder after `prefix`, or nil if it is not there.
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

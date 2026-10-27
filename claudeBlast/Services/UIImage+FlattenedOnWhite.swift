// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  UIImage+FlattenedOnWhite.swift
//  claudeBlast
//

import UIKit

extension UIImage {
    /// The picture on white, opaque.
    ///
    /// Tile art ships cut off its white ground (`TileCutout`). Inside the app a
    /// tile paints its colour behind it; anything that leaves the app — a
    /// picture export, an upload to the image edit endpoint — gets the white
    /// back, because a reader of a transparent PNG decides for itself what is
    /// behind it, and Photos and Word decide black or grey.
    func flattenedOnWhite() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

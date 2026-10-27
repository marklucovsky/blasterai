// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
// Command-line front end for claudeBlast/Services/TileCutout.swift, so the
// shipped sets are cut by the same code the app uses on art it generates.
//
//   tools/cutout/build.sh
//   tools/cutout/.build/cutout IN.png OUT.png [--all-white] [--holes x,y;…]
//   tools/cutout/.build/cutout --propose IN.png
//
// Cutting prints {"holesCut": n, "cleared": fraction}. Proposing prints
// {"holes": [[x, y], …], "edgeOnSubject": f}, for a person to confirm:
// enclosed ground Vision thinks is background (unit coordinates from the
// top-left), and how much of the edge cut Vision counts as the picture.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

func load(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(path)", 66) }
    return image
}

var args = Array(CommandLine.arguments.dropFirst())

if let i = args.firstIndex(of: "--propose") {
    args.remove(at: i)
    guard args.count == 1 else { fail("usage: cutout --propose IN.png", 64) }
    let found = TileCutout.propose(load(args[0])) ?? (holes: [], edgeOnSubject: 0)
    let list = found.holes.map { String(format: "[%.4f, %.4f]", $0.x, $0.y) }.joined(separator: ", ")
    print(#"{"holes": [\#(list)], "edgeOnSubject": \#(String(format: "%.4f", found.edgeOnSubject))}"#)
    exit(0)
}

var options = TileCutout.Options()
if let i = args.firstIndex(of: "--all-white") { options.clearAllWhite = true; args.remove(at: i) }
func points(after flag: String) -> [CGPoint] {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return [] }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1].split(separator: ";").compactMap { pair in
        let xy = pair.split(separator: ",").compactMap { Double($0) }
        return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
    }
}
options.holes = points(after: "--holes")
guard args.count == 2 else { fail("usage: cutout IN.png OUT.png [--all-white] [--holes x,y;…]", 64) }
guard let result = TileCutout.cut(load(args[0]), options: options),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else {
    fail("cut failed for \(args[0])", 70)
}
CGImageDestinationAddImage(dest, result.image, nil)
guard CGImageDestinationFinalize(dest) else { exit(73) }
print(#"{"holesCut": \#(result.holesCut), "cleared": \#(String(format: "%.4f", result.clearedFraction))}"#)

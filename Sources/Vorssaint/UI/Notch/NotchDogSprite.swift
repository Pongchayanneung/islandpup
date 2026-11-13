// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

/// Loads and caches the pixel-art dog's 144x128 RGBA walk frames (`walk_0.png`
/// ... `walk_7.png`, facing right) from `Bundle.main`'s `DogFrames` resource
/// subdirectory. `walk_0` is the standing pose.
enum NotchDogSprite {
    static let frames: [CGImage] = loadFrames()

    static var standing: CGImage? { frames.first }

    private static func loadFrames() -> [CGImage] {
        var result: [CGImage] = []
        result.reserveCapacity(8)
        for index in 0..<8 {
            guard let url = Bundle.main.url(forResource: "walk_\(index)", withExtension: "png",
                                            subdirectory: "DogFrames"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return []
            }
            result.append(image)
        }
        return result
    }
}

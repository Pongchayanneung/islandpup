// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

/// The pixel-art dog's animation actions, each loaded from `DogFrames/<action>_<n>.png`.
enum NotchDogAction: String, CaseIterable, Equatable {
    case walk, run, sprint, music, lowbat

    var frameCount: Int {
        switch self {
        case .walk: return 8
        case .run: return 10
        case .sprint: return 8
        case .music: return 8
        case .lowbat: return 6
        }
    }

    /// Gait used when the dog moves along a visit path.
    var visitGait: NotchDogAction {
        switch self {
        case .walk, .run, .sprint: return self
        case .music, .lowbat: return .walk
        }
    }
}

/// Loads and caches the pixel-art dog's 144x128 RGBA action frames
/// (`<action>_<n>.png`, facing right) from `Bundle.main`'s `DogFrames` resource
/// subdirectory. Missing non-walk actions fall back to `walk`.
enum NotchDogSprite {
    static var frames: [CGImage] { frames(for: .walk) }

    static var standing: CGImage? { frames(for: .walk).first }

    static func frames(for action: NotchDogAction) -> [CGImage] {
        cachedFrames[action] ?? []
    }

    static func frameInterval(for action: NotchDogAction) -> TimeInterval {
        switch action {
        case .walk: return 0.11
        case .run: return 0.06
        case .sprint: return 0.04
        case .music: return 0.12
        case .lowbat: return 0.30
        }
    }

    private static let cachedFrames: [NotchDogAction: [CGImage]] = {
        let walk = loadFrames(named: NotchDogAction.walk.rawValue, count: NotchDogAction.walk.frameCount)
        var result: [NotchDogAction: [CGImage]] = [.walk: walk]
        for action in NotchDogAction.allCases where action != .walk {
            let loaded = loadFrames(named: action.rawValue, count: action.frameCount)
            result[action] = loaded.isEmpty ? walk : loaded
        }
        return result
    }()

    private static func loadFrames(named prefix: String, count: Int) -> [CGImage] {
        var result: [CGImage] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            guard let url = Bundle.main.url(forResource: "\(prefix)_\(index)", withExtension: "png",
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

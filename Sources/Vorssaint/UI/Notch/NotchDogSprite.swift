// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

/// The pixel-art dog's animation actions, each loaded from `DogFrames/<action>_<n>.png`.
enum NotchDogAction: String, CaseIterable, Equatable {
    case walk, run, sprint, music, lowbat
    case charging, hot, latenight, wake, sleep, awake, working, focus, meeting, typing

    var frameCount: Int {
        switch self {
        case .walk: return 8
        case .run: return 10
        case .sprint: return 8
        case .music: return 8
        case .lowbat: return 6
        case .charging: return 8
        case .hot: return 8
        case .latenight: return 8
        case .wake: return 6
        case .sleep: return 6
        case .awake: return 6
        case .working: return 8
        case .focus: return 6
        case .meeting: return 6
        case .typing: return 8
        }
    }

    /// Gait used when the dog moves along a visit path.
    var visitGait: NotchDogAction {
        switch self {
        case .walk, .run, .sprint: return self
        case .music, .lowbat, .charging, .hot, .latenight, .wake, .sleep, .awake, .working, .focus, .meeting, .typing:
            return .walk
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
        if let pack = NotchDogPack.shared.active { return pack.frames[action] ?? [] }
        return cachedFrames[action] ?? []
    }

    /// Frames in `action`'s cycle: the chosen pack's, else the built-in count.
    static func frameCount(for action: NotchDogAction) -> Int {
        NotchDogPack.shared.active == nil ? action.frameCount : frames(for: action).count
    }

    static func frameInterval(for action: NotchDogAction) -> TimeInterval {
        if let override = NotchDogPack.shared.active?.intervals[action] { return override }
        return builtInInterval(for: action)
    }

    private static func builtInInterval(for action: NotchDogAction) -> TimeInterval {
        switch action {
        case .walk: return 0.11
        case .run: return 0.06
        case .sprint: return 0.04
        case .music: return 0.12
        case .lowbat: return 0.30
        case .charging: return 0.10
        case .hot: return 0.12
        case .latenight: return 0.30
        case .wake: return 0.12
        case .sleep: return 0.35
        case .awake: return 0.30
        case .working: return 0.14
        case .focus: return 0.30
        case .meeting: return 0.25
        case .typing: return 0.08
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

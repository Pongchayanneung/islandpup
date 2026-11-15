// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Character packs for the pixel dog: which folders count as a pack, how a
/// missing action falls back to the pack's own walk, and what the manifest sets.
enum NotchDogPackTests {
    private static let actions = ["walk", "run", "sprint", "sleep"]

    static func run(_ suite: TestSuite) {
        suite.run("NotchDogPack") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("dogpack-tests-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            packContracts(suite, root: root)
        }
    }

    private static func packContracts(_ suite: TestSuite, root: URL) {
        let fm = FileManager.default
        func folder(_ name: String) -> URL {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        // Walk only: valid, and every other action points at the walk frames.
        let walkOnly = folder("walkonly")
        writePNG(walkOnly.appendingPathComponent("walk_0.png"))
        writePNG(walkOnly.appendingPathComponent("walk_1.png"))
        let basic = NotchPackSupport.inspect(folder: walkOnly, actions: actions)
        suite.expect(basic != nil, "a folder with walk_0.png is a pack")
        suite.expect(basic?.displayName == "walkonly", "no manifest names the pack after its folder")
        suite.expect(basic?.flipped == false, "facing right by default")
        suite.expect(basic?.frames["walk"]?.count == 2, "frames run from 0 up to the first gap")
        for action in actions {
            suite.expect(basic?.frames[action] == basic?.frames["walk"], "\(action) falls back to walk")
        }
        suite.expect(basic?.intervals.isEmpty == true, "no manifest keeps the built-in intervals")

        // Own frames for run, manifest for name, facing and intervals.
        let full = folder("full")
        writePNG(full.appendingPathComponent("walk_0.png"))
        writePNG(full.appendingPathComponent("run_0.png"))
        writePNG(full.appendingPathComponent("run_1.png"))
        writePNG(full.appendingPathComponent("run_3.png"))
        let json = #"{"name":"  Cat  ","facing":"left","intervals":{"run":0.2,"walk":-1,"sleep":"x","nope":0.5,"sprint":99}}"#
        try? json.write(to: full.appendingPathComponent("pack.json"), atomically: true, encoding: .utf8)
        let info = NotchPackSupport.inspect(folder: full, actions: actions)
        suite.expect(info?.displayName == "Cat", "the manifest name is trimmed and used")
        suite.expect(info?.flipped == true, "facing left flips")
        suite.expect(info?.frames["run"]?.count == 2, "run keeps its own frames and stops at the gap")
        suite.expect(info?.frames["sleep"] == info?.frames["walk"], "sleep falls back to this pack's walk")
        suite.expect(info?.intervals["run"] == 0.2, "a manifest interval is used")
        suite.expect(info?.intervals["walk"] == nil, "a negative interval is ignored")
        suite.expect(info?.intervals["nope"] == nil, "an unknown action's interval is ignored")
        suite.expect(info?.intervals["sprint"] == NotchPackSupport.maxInterval, "an interval is clamped")

        // Invalid: no walk_0, not decodable, a file, and a broken manifest.
        let noWalk = folder("nowalk")
        writePNG(noWalk.appendingPathComponent("run_0.png"))
        suite.expect(NotchPackSupport.inspect(folder: noWalk, actions: actions) == nil, "no walk_0.png is not a pack")
        let corrupt = folder("corrupt")
        try? Data("not a png".utf8).write(to: corrupt.appendingPathComponent("walk_0.png"))
        suite.expect(NotchPackSupport.inspect(folder: corrupt, actions: actions) == nil, "an undecodable walk_0 is not a pack")
        try? Data().write(to: root.appendingPathComponent("stray.png"))
        let broken = folder("broken")
        writePNG(broken.appendingPathComponent("walk_0.png"))
        try? "{not json".write(to: broken.appendingPathComponent("pack.json"), atomically: true, encoding: .utf8)
        suite.expect(NotchPackSupport.inspect(folder: broken, actions: actions)?.displayName == "broken",
                     "a broken manifest leaves a usable pack with defaults")

        let names = NotchPackSupport.scan(root: root, actions: actions).map(\.displayName)
        suite.expect(names == ["broken", "Cat", "walkonly"], "scan lists only the valid packs, by name: \(names)")
        suite.expect(NotchPackSupport.scan(root: root.appendingPathComponent("missing"), actions: actions).isEmpty,
                     "a missing packs folder is an empty list")
    }

    private static func writePNG(_ url: URL, width: Int = 8, height: Int = 6) {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

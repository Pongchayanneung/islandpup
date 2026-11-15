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
            hardeningRules(suite, root: root)
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

    private static func hardeningRules(_ suite: TestSuite, root: URL) {
        let fm = FileManager.default
        let hardeningRoot = root.appendingPathComponent("hardening", isDirectory: true)
        try? fm.createDirectory(at: hardeningRoot, withIntermediateDirectories: true)
        func folder(_ name: String) -> URL {
            let url = hardeningRoot.appendingPathComponent(name, isDirectory: true)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        // 1. Invalid pack names rejected.
        for bad in ["", "   ", ".", "..", " . ", "a/b", "a\\b", "../escape"] {
            suite.expect(!NotchPackSupport.isValidPackName(bad), "rejects invalid pack name: \(bad)")
        }
        suite.expect(NotchPackSupport.isValidPackName("corgi"), "accepts normal pack name")

        // 2. Symlinks skipped for pack folder, frame files, and pack.json.
        let realPack = folder("real")
        writePNG(realPack.appendingPathComponent("walk_0.png"))
        let symPack = hardeningRoot.appendingPathComponent("sympack", isDirectory: true)
        try? fm.createSymbolicLink(at: symPack, withDestinationURL: realPack)
        suite.expect(NotchPackSupport.inspect(folder: symPack, actions: actions) == nil, "symlink pack folder is rejected")

        let symWalk = folder("symwalk")
        try? fm.createSymbolicLink(at: symWalk.appendingPathComponent("walk_0.png"),
                                   withDestinationURL: realPack.appendingPathComponent("walk_0.png"))
        suite.expect(NotchPackSupport.inspect(folder: symWalk, actions: actions) == nil, "symlink walk_0.png is rejected")

        let symAction = folder("symaction")
        writePNG(symAction.appendingPathComponent("walk_0.png"))
        writePNG(symAction.appendingPathComponent("run_0.png"))
        try? fm.createSymbolicLink(at: symAction.appendingPathComponent("run_1.png"),
                                   withDestinationURL: realPack.appendingPathComponent("walk_0.png"))
        let symManifestTarget = hardeningRoot.appendingPathComponent("external.json")
        try? #"{"name":"Symlinked"}"#.write(to: symManifestTarget, atomically: true, encoding: .utf8)
        try? fm.createSymbolicLink(at: symAction.appendingPathComponent("pack.json"), withDestinationURL: symManifestTarget)
        let symActionInfo = NotchPackSupport.inspect(folder: symAction, actions: actions)
        suite.expect(symActionInfo?.frames["run"]?.count == 1, "symlink run_1.png ends sequence at run_0.png")
        suite.expect(symActionInfo?.displayName == "symaction", "symlink pack.json is ignored")

        let scannedNames = NotchPackSupport.scan(root: hardeningRoot, actions: actions).map(\.folder)
        suite.expect(!scannedNames.contains("sympack"), "scan skips symlink pack folders")

        // 3. Oversized dimensions (> maxFrameSide) and oversized files (> 8 MB).
        let tallWalk = folder("tallwalk")
        writePNG(tallWalk.appendingPathComponent("walk_0.png"), width: NotchPackSupport.maxFrameSide + 1, height: 8)
        suite.expect(NotchPackSupport.inspect(folder: tallWalk, actions: actions) == nil,
                     "oversized walk_0.png makes pack invalid")

        let tallRun = folder("tallrun")
        writePNG(tallRun.appendingPathComponent("walk_0.png"))
        writePNG(tallRun.appendingPathComponent("run_0.png"))
        writePNG(tallRun.appendingPathComponent("run_1.png"), width: 8, height: NotchPackSupport.maxFrameSide + 1)
        suite.expect(NotchPackSupport.inspect(folder: tallRun, actions: actions)?.frames["run"]?.count == 1,
                     "oversized run_1.png ends run sequence at run_0.png")

        let bigWalk = folder("bigwalk")
        let bigWalkURL = bigWalk.appendingPathComponent("walk_0.png")
        writePNG(bigWalkURL)
        if var data = try? Data(contentsOf: bigWalkURL) {
            data.append(Data(count: NotchPackSupport.maxFrameBytes + 1))
            try? data.write(to: bigWalkURL)
        }
        suite.expect(NotchPackSupport.inspect(folder: bigWalk, actions: actions) == nil,
                     "frame larger than 8 MB makes walk_0.png invalid")

        // 4. pack.json > 64 KB or directory is treated as absent.
        let bigManifest = folder("bigmanifest")
        writePNG(bigManifest.appendingPathComponent("walk_0.png"))
        let padding = String(repeating: " ", count: NotchPackSupport.maxManifestBytes + 64)
        let oversizedJSON = #"{"name":"Ignored","pad":"\#(padding)"}"#
        try? oversizedJSON.write(to: bigManifest.appendingPathComponent("pack.json"), atomically: true, encoding: .utf8)
        suite.expect(NotchPackSupport.inspect(folder: bigManifest, actions: actions)?.displayName == "bigmanifest",
                     "oversized pack.json is treated as absent")

        let dirManifest = folder("dirmanifest")
        writePNG(dirManifest.appendingPathComponent("walk_0.png"))
        try? fm.createDirectory(at: dirManifest.appendingPathComponent("pack.json", isDirectory: true),
                                withIntermediateDirectories: true)
        suite.expect(NotchPackSupport.inspect(folder: dirManifest, actions: actions)?.displayName == "dirmanifest",
                     "directory pack.json is treated as absent")

        // 5. Cache stamp changes when a file is replaced with an older mtime or added.
        let stamped = folder("stamped")
        let w0 = stamped.appendingPathComponent("walk_0.png")
        let w1 = stamped.appendingPathComponent("walk_1.png")
        writePNG(w0)
        writePNG(w1)
        let now = Date()
        try? fm.setAttributes([.modificationDate: now], ofItemAtPath: w0.path)
        try? fm.setAttributes([.modificationDate: now.addingTimeInterval(-100)], ofItemAtPath: w1.path)
        let stamp1 = NotchPackSupport.inspect(folder: stamped, actions: actions)?.stamp
        try? fm.setAttributes([.modificationDate: now.addingTimeInterval(-200)], ofItemAtPath: w1.path)
        let stamp2 = NotchPackSupport.inspect(folder: stamped, actions: actions)?.stamp
        suite.expect(stamp1 != nil && stamp2 != nil && stamp1 != stamp2,
                     "replacing a file with an older mtime invalidates the cache stamp")

        let r0 = stamped.appendingPathComponent("run_0.png")
        writePNG(r0)
        try? fm.setAttributes([.modificationDate: now.addingTimeInterval(-300)], ofItemAtPath: r0.path)
        let stamp3 = NotchPackSupport.inspect(folder: stamped, actions: actions)?.stamp
        suite.expect(stamp3 != nil && stamp3 != stamp2,
                     "adding a file with an older mtime invalidates the cache stamp")
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

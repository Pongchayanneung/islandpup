// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import ImageIO

extension Notification.Name {
    /// The chosen character pack, or its files, changed: the dog redraws from the new frames.
    static let notchDogPackChanged = Notification.Name("NotchDogPackChanged")
}

/// Local fork: loads the character pack chosen in Settings (`notchDogPack`) and
/// hands `NotchDogSprite` its frames and intervals. Frames are decoded once per
/// pack folder and modification time, drawn at their own pixel size onto one
/// shared canvas with the built-in dog's 144:128 shape, bottom-centre aligned,
/// so every pack sits in the dog's box the way the built-in frames do.
final class NotchDogPack: @unchecked Sendable {
    static let shared = NotchDogPack()

    /// Frames of one pack, ready to hand to Core Animation.
    struct Loaded {
        let folder: String
        let name: String
        let stamp: NotchPackSupport.Stamp
        let frames: [NotchDogAction: [CGImage]]
        let intervals: [NotchDogAction: TimeInterval]
    }

    private static let canvasAspect: CGFloat = 144.0 / 128.0
    private static let maxSide = NotchPackSupport.maxFrameSide
    private static let recheckInterval: TimeInterval = 2

    private let lock = NSLock()
    private var cached: Loaded?
    private var cachedName = ""
    private var checkedAt: TimeInterval = 0
    private var scanned: [NotchPackSupport.Info]?

    private init() {}

    private static var actionNames: [String] { NotchDogAction.allCases.map(\.rawValue) }

    /// The folder name stored in the preference; empty is the built-in dog.
    var selectedName: String {
        let raw = UserDefaults.standard.string(forKey: NotchPackSupport.defaultsKey) ?? ""
        return NotchPackSupport.isValidPackName(raw) ? raw : ""
    }

    /// The chosen pack when it is valid, else nil and the built-in dog is used.
    /// The folder is re-inspected at most every `recheckInterval` seconds, which
    /// keeps the per-frame lookups cheap and still notices an edited pack.
    var active: Loaded? {
        lock.lock()
        defer { lock.unlock() }
        let name = selectedName
        guard !name.isEmpty else {
            cached = nil
            cachedName = ""
            checkedAt = 0
            return nil
        }
        let now = ProcessInfo.processInfo.systemUptime
        if cachedName == name, now - checkedAt < Self.recheckInterval { return cached }
        let folder = NotchPackSupport.packsRoot.appendingPathComponent(name, isDirectory: true)
        cachedName = name
        checkedAt = now
        guard let info = NotchPackSupport.inspect(folder: folder, actions: Self.actionNames) else {
            cached = nil
            return nil
        }
        if let cached, cached.stamp == info.stamp, cached.folder == name { return cached }
        cached = Self.load(info)
        return cached
    }

    /// Every valid pack in the packs folder, as of the last `reload()`.
    var packs: [NotchPackSupport.Info] {
        lock.lock()
        defer { lock.unlock() }
        if let scanned { return scanned }
        let found = NotchPackSupport.scan(root: NotchPackSupport.packsRoot, actions: Self.actionNames)
        scanned = found
        return found
    }

    /// A fresh scan of the packs folder, without redrawing the dog.
    func rescan() -> [NotchPackSupport.Info] {
        lock.lock()
        scanned = nil
        lock.unlock()
        return packs
    }

    /// Choose a pack by folder name; empty chooses the built-in dog.
    func select(_ name: String) {
        let sanitized = NotchPackSupport.isValidPackName(name) ? name : ""
        lock.lock()
        UserDefaults.standard.set(sanitized, forKey: NotchPackSupport.defaultsKey)
        if sanitized.isEmpty {
            cached = nil
            cachedName = ""
            checkedAt = 0
        }
        lock.unlock()
        changed()
    }

    /// Rescan the folder and redraw, for packs added or edited while the app runs.
    func reload() {
        lock.lock()
        scanned = nil
        cached = nil
        cachedName = ""
        lock.unlock()
        changed()
    }

    private func changed() {
        let post = { NotificationCenter.default.post(name: .notchDogPackChanged, object: nil) }
        if Thread.isMainThread { post() } else { DispatchQueue.main.async(execute: post) }
    }

    /// Creates the packs folder if needed and shows it in Finder.
    @MainActor
    func openFolder() {
        let root = NotchPackSupport.packsRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    // MARK: Decoding

    private static func load(_ info: NotchPackSupport.Info) -> Loaded {
        let walkURLs = info.frames["walk"] ?? []
        let walk = walkURLs.compactMap(image(at:))
        var decoded: [String: [CGImage]] = ["walk": walk]
        for (action, urls) in info.frames where action != "walk" && urls != walkURLs {
            decoded[action] = urls.compactMap(image(at:))
        }
        let all = decoded.values.flatMap { $0 }
        let width = max(all.map(\.width).max() ?? 1, Int((CGFloat(all.map(\.height).max() ?? 1) * canvasAspect).rounded(.up)))
        let height = max(1, Int((CGFloat(width) / canvasAspect).rounded(.up)))

        let walkFrames = walk.compactMap { place($0, width: width, height: height, flipped: info.flipped) }
        var frames: [NotchDogAction: [CGImage]] = [:]
        var intervals: [NotchDogAction: TimeInterval] = [:]
        for action in NotchDogAction.allCases {
            if let images = decoded[action.rawValue], !images.isEmpty, action != .walk {
                frames[action] = images.compactMap { place($0, width: width, height: height, flipped: info.flipped) }
            } else {
                frames[action] = walkFrames
            }
            if let value = info.intervals[action.rawValue] { intervals[action] = value }
        }
        return Loaded(folder: info.folder, name: info.displayName, stamp: info.stamp, frames: frames, intervals: intervals)
    }

    private static func image(at url: URL) -> CGImage? {
        guard NotchPackSupport.isWithinLimits(url, maxSide: maxSide),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        if let image = CGImageSourceCreateImageAtIndex(source, 0, nil), max(image.width, image.height) <= maxSide {
            return image
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxSide]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Draws `image` at its own size, bottom-centre, on a transparent canvas.
    private static func place(_ image: CGImage, width: Int, height: Int, flipped: Bool) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        if flipped {
            context.translateBy(x: CGFloat(width), y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        // Bottom-up coordinates: y 0 is the canvas floor, where the feet stand.
        let x = CGFloat((width - image.width) / 2)
        context.draw(image, in: CGRect(x: x, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        return context.makeImage()
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation

/// Computes the pixel dog's current action from system state while at least
/// one dog mascot is visible.
@MainActor
final class NotchDogState: ObservableObject {
    static let shared = NotchDogState()

    @Published private(set) var action: NotchDogAction = .walk

    private var visibleClients = 0
    private var fastTimer: Timer?
    private var sampleTimer: Timer?
    private var wakeWork: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()
    private var centerObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var defaultsObserver: NSObjectProtocol?

    private let cpuQueue = DispatchQueue(label: "com.vorssaint.notch-dog-cpu", qos: .utility)
    private let cpuSampler = CPUCoreSampler()
    private let claudeMonitor = ClaudeProcessMonitor()
    private var samplingInFlight = false
    private var smoothedCPU: Double?
    private var cpuGait: NotchDogAction = .walk
    private var micInUse = false
    private var claudeBusy = false
    private var wakeUntil: TimeInterval = -.infinity
    private var lastActionChange: TimeInterval = -.infinity

    private static let fastInterval: TimeInterval = 1.0
    private static let sampleInterval: TimeInterval = 2.0
    private static let dwellSeconds: TimeInterval = 3.0
    private static let idleThresholdSeconds: TimeInterval = 120.0
    private static let typingThresholdSeconds: TimeInterval = 1.5
    private static let wakeDuration: TimeInterval =
        Double(NotchDogAction.wake.frameCount) * NotchDogSprite.frameInterval(for: .wake) + 0.3

    private init() {}

    /// Tracks how many `.dog` mascot views are currently visible on screen so
    /// detectors and CPU sampling only run when needed.
    func setClientVisible(_ visible: Bool) {
        let wasActive = visibleClients > 0
        visibleClients = max(0, visibleClients + (visible ? 1 : -1))
        let isActive = visibleClients > 0
        guard isActive != wasActive else { return }
        if isActive {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        NotchService.shared.$power
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &subscriptions)

        NotchMusicService.shared.$playback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &subscriptions)

        KeepAwakeManager.shared.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &subscriptions)

        NotchTimerService.shared.$session
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &subscriptions)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let observer = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleWake()
                }
            }
            centerObservers.append((workspaceCenter, observer))
        }

        let distributedCenter = DistributedNotificationCenter.default()
        let unlockObserver = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWake()
            }
        }
        centerObservers.append((distributedCenter, unlockObserver))

        #if VORSSAINT_DEVELOPMENT
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluate()
            }
        }
        #endif

        let fastTimer = Timer(timeInterval: Self.fastInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fastTick()
            }
        }
        RunLoop.main.add(fastTimer, forMode: .common)
        self.fastTimer = fastTimer

        let sampleTimer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleTick()
            }
        }
        RunLoop.main.add(sampleTimer, forMode: .common)
        self.sampleTimer = sampleTimer

        evaluate()
        sampleTick()
    }

    private func stop() {
        fastTimer?.invalidate()
        fastTimer = nil
        sampleTimer?.invalidate()
        sampleTimer = nil
        wakeWork?.cancel()
        wakeWork = nil
        wakeUntil = -.infinity
        subscriptions.removeAll()
        for (center, observer) in centerObservers {
            center.removeObserver(observer)
        }
        centerObservers.removeAll()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        smoothedCPU = nil
        cpuGait = .walk
        micInUse = false
        claudeBusy = false
        lastActionChange = -.infinity
        cpuQueue.async { [cpuSampler, claudeMonitor] in
            cpuSampler.reset()
            claudeMonitor.reset()
        }
    }

    private func handleWake() {
        guard visibleClients > 0 else { return }
        wakeUntil = ProcessInfo.processInfo.systemUptime + Self.wakeDuration
        wakeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.wakeWork = nil
            self?.evaluate()
        }
        wakeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeDuration, execute: work)
        evaluate()
    }

    private func fastTick() {
        guard visibleClients > 0 else { return }
        evaluate()
    }

    private func sampleTick() {
        guard visibleClients > 0, !samplingInFlight else { return }
        samplingInFlight = true
        let now = ProcessInfo.processInfo.systemUptime
        cpuQueue.async { [weak self, cpuSampler, claudeMonitor] in
            let samples = cpuSampler.sample(now: now).compactMap { $0 }
            let rawCPU = samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count)
            let mic = AudioInputDetector.micInUse()
            let claude = claudeMonitor.isWorking(now: now)
            DispatchQueue.main.async {
                guard let self else { return }
                self.samplingInFlight = false
                guard self.visibleClients > 0 else { return }
                if let rawCPU {
                    let smoothed = self.smoothedCPU.map { 0.6 * $0 + 0.4 * rawCPU } ?? rawCPU
                    self.smoothedCPU = smoothed
                    self.updateCPUGait(cpu: smoothed)
                }
                self.micInUse = mic
                self.claudeBusy = claude
                self.evaluate()
            }
        }
    }

    private func updateCPUGait(cpu: Double) {
        switch cpuGait {
        case .walk:
            if cpu >= 0.50 { cpuGait = .sprint }
            else if cpu >= 0.25 { cpuGait = .run }
            else { cpuGait = .walk }
        case .run:
            if cpu >= 0.50 { cpuGait = .sprint }
            else if cpu < 0.13 { cpuGait = .walk }
            else { cpuGait = .run }
        case .sprint:
            if cpu < 0.38 { cpuGait = cpu >= 0.20 ? .run : .walk }
            else { cpuGait = .sprint }
        default:
            cpuGait = .walk
        }
    }

    private func evaluate() {
        let now = ProcessInfo.processInfo.systemUptime
        #if VORSSAINT_DEVELOPMENT
        if let forced = UserDefaults.standard.string(forKey: "notchDogForceAction")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           let forcedAction = NotchDogAction(rawValue: forced) {
            if forcedAction != action {
                action = forcedAction
                lastActionChange = now
                NotificationCenter.default.post(name: .notchMascotDogActionChanged, object: self)
            }
            return
        }
        #endif

        let next = computeAction(now: now)
        guard next != action else { return }
        if action.isCalm, next.isCalm, now - lastActionChange < Self.dwellSeconds {
            return
        }
        action = next
        lastActionChange = now
        NotificationCenter.default.post(name: .notchMascotDogActionChanged, object: self)
    }

    private func computeAction(now: TimeInterval) -> NotchDogAction {
        if isLowBattery() {
            return .lowbat
        }
        if now < wakeUntil {
            return .wake
        }
        if isIdle() {
            return KeepAwakeManager.shared.isActive ? .awake : .sleep
        }
        if isHot() {
            return .hot
        }
        if micInUse {
            return .meeting
        }
        if NotchTimerService.shared.session.isRunning {
            return .focus
        }
        if claudeBusy {
            return .working
        }
        if NotchMusicService.shared.playback?.isPlaying == true {
            return .music
        }
        if isTyping() {
            return .typing
        }
        if cpuGait != .walk {
            return cpuGait
        }
        if isLateNight() {
            return .latenight
        }
        if isCharging() {
            return .charging
        }
        return .walk
    }

    private func isLowBattery() -> Bool {
        let power = NotchService.shared.power
        if power.hasBattery, let percent = power.chargePercent {
            return percent <= 20 && !power.isCharging
        }
        if let snapshot = SystemInfo.batterySnapshot() {
            return snapshot.percent <= 20 && !snapshot.isCharging
        }
        return false
    }

    private func isCharging() -> Bool {
        let power = NotchService.shared.power
        if power.hasBattery, power.chargePercent != nil {
            return power.isCharging
        }
        if let snapshot = SystemInfo.batterySnapshot() {
            return snapshot.isCharging
        }
        return false
    }

    private func isIdle() -> Bool {
        let eventType = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: eventType) >= Self.idleThresholdSeconds
    }

    private func isTyping() -> Bool {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < Self.typingThresholdSeconds
    }

    private func isHot() -> Bool {
        ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    private func isLateNight() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 23 || hour < 5
    }
}

private extension NotchDogAction {
    var isCalm: Bool {
        switch self {
        case .walk, .run, .sprint, .charging, .latenight, .music, .working, .focus, .meeting, .typing:
            return true
        case .lowbat, .wake, .sleep, .awake, .hot:
            return false
        }
    }
}

private enum AudioInputDetector {
    static func micInUse() -> Bool {
        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObj = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObj, &listAddr, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let capacity = Int(size) / MemoryLayout<AudioObjectID>.stride
        guard capacity > 0 else { return false }

        var objects = [AudioObjectID](repeating: 0, count: capacity)
        guard AudioObjectGetPropertyData(systemObj, &listAddr, 0, nil, &size, &objects) == noErr else {
            return false
        }
        let count = min(capacity, Int(size) / MemoryLayout<AudioObjectID>.stride)

        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for obj in objects.prefix(count) {
            var running: UInt32 = 0
            var propSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(obj, &propAddr, 0, nil, &propSize, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}

private final class ClaudeProcessMonitor {
    private var prevCpuNs: [pid_t: UInt64] = [:]
    private var prevSampleTime: TimeInterval?
    private var lastBusyTime: TimeInterval?
    private var lastAnswer = false

    func reset() {
        prevCpuNs.removeAll()
        prevSampleTime = nil
        lastBusyTime = nil
        lastAnswer = false
    }

    func isWorking(now: TimeInterval) -> Bool {
        if let prevSampleTime, now - prevSampleTime < 0.5 {
            return lastAnswer
        }

        let current = sampleClaudeCpuNs()
        guard let prevSampleTime else {
            prevCpuNs = current
            self.prevSampleTime = now
            lastAnswer = false
            return false
        }

        let intervalNs = (now - prevSampleTime) * 1_000_000_000.0
        var isBusyNow = false
        if intervalNs > 0 {
            for (pid, cpuNs) in current {
                if let prevNs = prevCpuNs[pid], cpuNs >= prevNs {
                    let usage = Double(cpuNs - prevNs) / intervalNs
                    if usage >= 0.05 {
                        isBusyNow = true
                        break
                    }
                }
            }
        }

        prevCpuNs = current
        self.prevSampleTime = now

        if isBusyNow {
            lastBusyTime = now
            lastAnswer = true
        } else if let lastBusyTime, now - lastBusyTime <= 3.0 {
            lastAnswer = true
        } else {
            lastAnswer = false
        }
        return lastAnswer
    }

    private func sampleClaudeCpuNs() -> [pid_t: UInt64] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [:] }

        var pids = [pid_t](repeating: 0, count: Int(estimated) + 32)
        let byteSize = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let actualCount = pids.withUnsafeMutableBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return 0 }
            return proc_listallpids(base, byteSize)
        }
        guard actualCount > 0 else { return [:] }

        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let numer = UInt64(tb.numer)
        let denom = UInt64(max(tb.denom, 1))

        var result: [pid_t: UInt64] = [:]
        var nameBuf = [CChar](repeating: 0, count: 64)
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        let count = min(Int(actualCount), pids.count)

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let nameLen = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            guard nameLen > 0 else { continue }
            nameBuf[nameBuf.count - 1] = 0
            let isClaude = nameBuf.withUnsafeBufferPointer { ptr -> Bool in
                guard let base = ptr.baseAddress else { return false }
                return strcmp(base, "claude") == 0
            }
            guard isClaude else { continue }

            var info = proc_taskinfo()
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize)
            guard ret == infoSize else { continue }

            let totalMach = info.pti_total_user &+ info.pti_total_system
            let cpuNs = (totalMach / denom) &* numer &+ ((totalMach % denom) &* numer) / denom
            result[pid] = cpuNs
        }
        return result
    }
}

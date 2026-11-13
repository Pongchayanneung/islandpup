// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Computes the pixel dog's current action from system state (priority:
/// lowbat > music > CPU gait) while at least one dog mascot is visible.
@MainActor
final class NotchDogState: ObservableObject {
    static let shared = NotchDogState()

    @Published private(set) var action: NotchDogAction = .walk

    private var visibleClients = 0
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var defaultsObserver: NSObjectProtocol?

    private let cpuQueue = DispatchQueue(label: "com.vorssaint.notch-dog-cpu", qos: .utility)
    private let cpuSampler = CPUCoreSampler()
    private var cpuSamplingInFlight = false
    private var cpuGait: NotchDogAction = .walk
    private var lastGaitChange: TimeInterval = -.infinity

    private static let sampleInterval: TimeInterval = 2.0
    private static let gaitDwellSeconds: TimeInterval = 3.0

    private init() {}

    /// Tracks how many `.dog` mascot views are currently visible on screen so
    /// CPU sampling only runs when needed.
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

        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        evaluate()
        sampleTick()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        subscriptions.removeAll()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        cpuGait = .walk
        lastGaitChange = -.infinity
        cpuQueue.async { [cpuSampler] in
            cpuSampler.reset()
        }
    }

    private func sampleTick() {
        guard visibleClients > 0, !cpuSamplingInFlight else { return }
        cpuSamplingInFlight = true
        let now = ProcessInfo.processInfo.systemUptime
        cpuQueue.async { [weak self, cpuSampler] in
            let samples = cpuSampler.sample(now: now).compactMap { $0 }
            let cpu = samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count)
            DispatchQueue.main.async {
                guard let self else { return }
                self.cpuSamplingInFlight = false
                guard self.visibleClients > 0 else { return }
                if let cpu {
                    self.updateCPUGait(cpu: cpu, now: now)
                }
                self.evaluate()
            }
        }
    }

    private func updateCPUGait(cpu: Double, now: TimeInterval) {
        let target: NotchDogAction
        switch cpuGait {
        case .walk:
            if cpu >= 0.75 { target = .sprint }
            else if cpu >= 0.375 { target = .run }
            else { target = .walk }
        case .run:
            if cpu >= 0.75 { target = .sprint }
            else if cpu < 0.195 { target = .walk }
            else { target = .run }
        case .sprint:
            if cpu < 0.195 { target = .walk }
            else if cpu < 0.63 { target = .run }
            else { target = .sprint }
        case .music, .lowbat:
            target = .walk
        }
        guard target != cpuGait, now - lastGaitChange >= Self.gaitDwellSeconds else { return }
        cpuGait = target
        lastGaitChange = now
    }

    private func evaluate() {
        let next = computeAction()
        guard next != action else { return }
        action = next
        NotificationCenter.default.post(name: .notchMascotDogActionChanged, object: self)
    }

    private func computeAction() -> NotchDogAction {
        #if VORSSAINT_DEVELOPMENT
        if let forced = UserDefaults.standard.string(forKey: "notchDogForceAction")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           let forcedAction = NotchDogAction(rawValue: forced) {
            return forcedAction
        }
        #endif

        if isLowBattery() {
            return .lowbat
        }
        if NotchMusicService.shared.playback?.isPlaying == true {
            return .music
        }
        return cpuGait
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
}

import SwiftUI
import UIKit
import Observation

/// Decides how much visual effect work the device should do right now.
///
/// Combines the system accessibility settings, Low Power Mode, thermal pressure and the
/// user's own preference, so every animated surface in the app asks one place.
@MainActor
@Observable
final class EffectsBudget {
    enum Level: Int, Comparable {
        /// Static artwork-tinted gradients only.
        case still = 0
        /// Shaders run at a reduced frame rate with fewer particles.
        case calm = 1
        /// Full-rate shaders, particles, parallax.
        case full = 2

        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    private(set) var reduceMotion = UIAccessibility.isReduceMotionEnabled
    private(set) var reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
    private(set) var increaseContrast = UIAccessibility.isDarkerSystemColorsEnabled
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var thermal = ProcessInfo.processInfo.thermalState

    /// User preference from Settings ("Cinematic", "Balanced", "Minimal").
    var preference: Level = .full

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            .NSProcessInfoPowerStateDidChange,
            ProcessInfo.thermalStateDidChangeNotification
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(token)
        }
    }

    func refresh() {
        reduceMotion = UIAccessibility.isReduceMotionEnabled
        reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        increaseContrast = UIAccessibility.isDarkerSystemColorsEnabled
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermal = ProcessInfo.processInfo.thermalState
    }

    var level: Level {
        if reduceMotion { return .still }
        var system: Level = .full
        if lowPower || thermal == .serious { system = .calm }
        if thermal == .critical { system = .still }
        return min(system, preference)
    }

    var animatesBackgrounds: Bool { level > .still }
    var allowsParallax: Bool { level == .full }
    var allowsPhysics: Bool { !reduceMotion }

    /// Frame interval for TimelineView-driven shaders.
    var frameInterval: Double { level == .full ? 1.0 / 120.0 : 1.0 / 30.0 }

    /// Multiplier applied to particle density in shaders.
    var particleScale: Double {
        switch level {
        case .still: return 0.6
        case .calm: return 0.55
        case .full: return 1
        }
    }

    /// Glass needs a solid fallback when transparency is reduced or contrast increased.
    var prefersSolidSurfaces: Bool { reduceTransparency || increaseContrast }

    var statusSummary: String {
        if reduceMotion { return "Reduce Motion is on, so backgrounds stay still." }
        if thermal == .critical { return "The device is hot, so effects are paused." }
        if lowPower { return "Low Power Mode is on, so effects run at a gentler frame rate." }
        if thermal == .serious { return "The device is warm, so effects are scaled back." }
        switch preference {
        case .full: return "Full effects."
        case .calm: return "Balanced effects."
        case .still: return "Minimal effects."
        }
    }
}

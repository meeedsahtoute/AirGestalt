//
//  GhostAppIntents.swift
//  AirGestalt
//
//  iOS System App Intents for Control Center, Action Button, Siri & Shortcuts.
//  Enables instant toggling of Ghost Mode Transparency & Find My Chirp without opening the app.
//

import Foundation
import AppIntents

// MARK: - Toggle Ghost Mode & Transparency Intent

public struct ToggleGhostTransparencyIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Ghost Transparency"
    public static var description = IntentDescription("Toggles AirGestalt Ghost Mode and real-time microphone transparency passthrough.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = GhostAudioEngine.shared
        let newState = !engine.isSoftwareTransparencyActive
        engine.setTransparencyActive(newState)

        let status = newState ? "Ghost Mode Active: Real-time mic transparency enabled" : "Ghost Mode Off: Transparency passthrough disabled"
        return .result(dialog: IntentDialog(stringLiteral: status))
    }
}

// MARK: - Trigger Find My Chirp Intent

public struct TriggerFindMyChirpIntent: AppIntent {
    public static var title: LocalizedStringResource = "Play Find My Chirp"
    public static var description = IntentDescription("Plays an acoustic beacon chirp to locate nearby connected earbuds.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        SpatialDSPEngine.shared.playFindMyChirp()
        return .result(dialog: IntentDialog(stringLiteral: "Emitting Find My acoustic chirp beacon."))
    }
}

// MARK: - Toggle Ghost Mode Background DSP Intent

public struct ToggleGhostModeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Ghost Mode"
    public static var description = IntentDescription("Enables or disables AirGestalt persistent background DSP processing.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = GhostAudioEngine.shared
        let newState = !engine.isGhostModeActive
        engine.setGhostModeActive(newState)

        let status = newState ? "Ghost Mode Background DSP Enabled" : "Ghost Mode Background DSP Disabled"
        return .result(dialog: IntentDialog(stringLiteral: status))
    }
}

// MARK: - Shortcuts Provider (Action Button & Shortcuts Integration)

public struct AirGestaltShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleGhostTransparencyIntent(),
            phrases: [
                "Toggle \(.applicationName) Transparency",
                "Toggle Ghost Mode in \(.applicationName)",
                "Switch \(.applicationName) Passthrough"
            ],
            shortTitle: "Ghost Transparency",
            systemImageName: "waveform.badge.mic"
        )
        AppShortcut(
            intent: TriggerFindMyChirpIntent(),
            phrases: [
                "Find my earbuds with \(.applicationName)",
                "Play chirp in \(.applicationName)",
                "Where are my earbuds in \(.applicationName)"
            ],
            shortTitle: "Find My Chirp",
            systemImageName: "speaker.wave.3.fill"
        )
        AppShortcut(
            intent: ToggleGhostModeIntent(),
            phrases: [
                "Activate Ghost Mode in \(.applicationName)",
                "Toggle \(.applicationName) Ghost Mode"
            ],
            shortTitle: "Ghost Mode",
            systemImageName: "waveform.circle.fill"
        )
    }
}

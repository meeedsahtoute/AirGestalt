//
//  AirGestaltApp.swift
//  AirGestalt
//
//  Main Application Entry Point.
//  Initializes Audio Pipeline safely with route-change resiliency,
//  Continuity BLE scanning, and haptic feedback.
//

import SwiftUI
import AVFoundation

@main
struct AirGestaltApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Safely start SharedAudioEngine and prepare haptics
        do {
            try SharedAudioEngine.shared.startEngine()
        } catch {
            print("Audio engine initialization deferred: \(error)")
        }

        HapticFeedbackManager.shared.prepare()
        return true
    }
}

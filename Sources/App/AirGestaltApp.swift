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
        // Lazy Audio Engine: Do NOT activate AVAudioSession on launch to prevent pausing background music
        HapticFeedbackManager.shared.prepare()
        return true
    }
}

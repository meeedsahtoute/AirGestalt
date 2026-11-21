//
//  AirGestaltApp.swift
//  AirGestalt
//
//  Main Application Entry Point.
//  Coordinates Shared Audio Engine input taps, Bluetooth Continuity Scanner,
//  and background lifecycle events.
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
        // Prepare audio tap and haptics
        setupGlobalAudioPipeline()
        HapticFeedbackManager.shared.prepare()
        return true
    }

    private func setupGlobalAudioPipeline() {
        let engine = SharedAudioEngine.shared.engine
        let inputNode = engine.inputNode

        // Install audio tap on inputNode for real-time DSP, VU metering, and latency measurement
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, _ in
            // Forward buffer to DSP anti-noise processor
            _ = VDSPAntiNoiseProcessor.shared.processInputBuffer(buffer)

            // Forward buffer to VU meter and noise gate in ProMicEngine
            ProMicEngine.shared.processMicrophoneBuffer(buffer)

            // If latency calibrator is active, forward raw microphone samples
            if AutoLatencyCalibrator.shared.isCalibrating,
               let channel = buffer.floatChannelData?[0] {
                AutoLatencyCalibrator.shared.appendMicrophoneSamples(channel, count: Int(buffer.frameLength))
            }
        }

        // Configure hardware voice processing
        ProMicEngine.shared.configureVoiceProcessing(on: inputNode)
    }
}

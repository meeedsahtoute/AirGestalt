//
//  SharedAudioEngine.swift
//  AirGestalt
//
//  Single Shared AVAudioEngine & Zero-Downgrade A2DP Session Coordinator.
//  Routes iPhone built-in microphone for reference input while keeping Bluetooth
//  A2DP playback at full high-resolution fidelity without HFP degradation.
//

import Foundation
import AVFoundation
import Combine

public final class SharedAudioEngine: ObservableObject {
    public static let shared = SharedAudioEngine()

    public let engine = AVAudioEngine()
    public let playerNode = AVAudioPlayerNode()
    public let mainMixer: AVAudioMixerNode

    @Published public var isRunning: Bool = false
    @Published public var currentInputSampleRate: Double = 48000.0
    @Published public var preferredMicPort: String = "Built-In Microphone"
    @Published public var isUsingEarbudMic: Bool = false

    private init() {
        self.mainMixer = engine.mainMixerNode
        engine.attach(playerNode)
        engine.connect(playerNode, to: mainMixer, format: nil)
    }

    public func configureAudioSession(forceEarbudMic: Bool = false) throws {
        let session = AVAudioSession.sharedInstance()

        self.isUsingEarbudMic = forceEarbudMic

        if forceEarbudMic {
            // Mode for A/B testing with earbud native microphone
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
        } else {
            // High-fidelity Zero-Downgrade routing: strictly allowBluetoothA2DP, NO allowBluetooth
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP, .defaultToSpeaker])

            // Route to iPhone studio microphone
            if let inputs = session.availableInputs {
                if let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
                    try session.setPreferredInput(builtInMic)
                    DispatchQueue.main.async {
                        self.preferredMicPort = builtInMic.portName
                    }
                }
            }
        }

        try session.setPreferredSampleRate(48000.0)
        try session.setPreferredIOBufferDuration(0.00533) // ~256 frames at 48kHz for low latency
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        DispatchQueue.main.async {
            self.currentInputSampleRate = session.sampleRate
        }
    }

    public func startEngine() throws {
        guard !engine.isRunning else { return }
        try configureAudioSession(forceEarbudMic: isUsingEarbudMic)
        try engine.start()
        if !playerNode.isPlaying {
            playerNode.play()
        }
        DispatchQueue.main.async {
            self.isRunning = true
        }
    }

    public func stopEngine() {
        guard engine.isRunning else { return }
        playerNode.stop()
        engine.stop()
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }
}

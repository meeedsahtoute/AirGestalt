//
//  SharedAudioEngine.swift
//  AirGestalt
//
//  Single Shared AVAudioEngine & Resilient Audio Session Coordinator.
//  Protects against format and channel-count mismatches, handles route changes dynamically,
//  and provides converter-backed safe buffer scheduling.
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
    @Published public var inputChannelCount: Int = 1

    private var isTapInstalled: Bool = false
    private let engineQueue = DispatchQueue(label: "com.airgestalt.audioengine.queue", qos: .userInitiated)

    public static let canonicalFormat = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 2)

    private init() {
        self.mainMixer = engine.mainMixerNode
        engine.attach(playerNode)

        // Connect playerNode to mainMixer with canonical stereo format
        if let format = SharedAudioEngine.canonicalFormat {
            engine.connect(playerNode, to: mainMixer, format: format)
        } else {
            engine.connect(playerNode, to: mainMixer, format: nil)
        }

        setupNotificationObservers()
    }

    // MARK: - Safe Audio Session Configuration

    public func configureAudioSession(forceEarbudMic: Bool = false) throws {
        let session = AVAudioSession.sharedInstance()
        self.isUsingEarbudMic = forceEarbudMic

        // Safe resilient audio session options supporting Bluetooth, A2DP, mixing, and speaker routing
        let sessionOptions: AVAudioSession.CategoryOptions = [
            .allowBluetooth,
            .allowBluetoothA2DP,
            .mixWithOthers,
            .defaultToSpeaker
        ]

        try session.setCategory(.playAndRecord, mode: .default, options: sessionOptions)

        if !forceEarbudMic {
            if let inputs = session.availableInputs,
               let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtInMic)
                DispatchQueue.main.async {
                    self.preferredMicPort = builtInMic.portName
                }
            }
        }

        try? session.setPreferredSampleRate(48000.0)
        try? session.setPreferredIOBufferDuration(0.00533)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        DispatchQueue.main.async {
            self.currentInputSampleRate = session.sampleRate
        }
    }

    // MARK: - Engine Lifecycle

    public func startEngine() throws {
        guard !engine.isRunning else { return }

        try configureAudioSession(forceEarbudMic: isUsingEarbudMic)

        // Ensure nodes are connected
        ensureNodesConnected()

        try engine.start()
        if !playerNode.isPlaying {
            playerNode.play()
        }

        installInputTapSafely()

        DispatchQueue.main.async {
            self.isRunning = true
        }
    }

    public func stopEngine() {
        guard engine.isRunning else { return }
        removeInputTapSafely()
        playerNode.stop()
        engine.stop()
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    private func ensureNodesConnected() {
        let targetFormat = playerNode.outputFormat(forBus: 0)
        if targetFormat.channelCount == 0 || targetFormat.sampleRate == 0 {
            if let canonical = SharedAudioEngine.canonicalFormat {
                engine.disconnectNodeOutput(playerNode)
                engine.connect(playerNode, to: mainMixer, format: canonical)
            }
        }
    }

    // MARK: - Safe Buffer Scheduling (Zero Channel-Mismatch Guarantee)

    public func scheduleBufferSafely(_ buffer: AVAudioPCMBuffer) {
        engineQueue.async { [weak self] in
            guard let self = self else { return }

            if !self.engine.isRunning {
                do {
                    try self.startEngine()
                } catch {
                    print("SharedAudioEngine start error: \(error)")
                    return
                }
            }

            self.ensureNodesConnected()

            let outputFormat = self.playerNode.outputFormat(forBus: 0)
            guard outputFormat.channelCount > 0, outputFormat.sampleRate > 0 else { return }

            // 1. Direct match
            if buffer.format.channelCount == outputFormat.channelCount &&
               abs(buffer.format.sampleRate - outputFormat.sampleRate) < 1.0 {
                self.playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
                if !self.playerNode.isPlaying { self.playerNode.play() }
                return
            }

            // 2. Hardware channel mismatch conversion (Mono to Stereo)
            if let converted = self.convertBuffer(buffer, to: outputFormat) {
                self.playerNode.scheduleBuffer(converted, at: nil, options: [], completionHandler: nil)
                if !self.playerNode.isPlaying { self.playerNode.play() }
                return
            }

            // 3. Fallback stereo channel duplication
            if outputFormat.channelCount == 2 && buffer.format.channelCount == 1 {
                if let stereo = self.createStereoBuffer(fromMono: buffer, targetFormat: outputFormat) {
                    self.playerNode.scheduleBuffer(stereo, at: nil, options: [], completionHandler: nil)
                    if !self.playerNode.isPlaying { self.playerNode.play() }
                }
            }
        }
    }

    private func convertBuffer(_ inputBuffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: inputBuffer.format, to: targetFormat) else {
            return nil
        }

        let ratio = targetFormat.sampleRate / max(1.0, inputBuffer.format.sampleRate)
        let capacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var isConsumed = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if !isConsumed {
                outStatus.pointee = .haveData
                isConsumed = true
                return inputBuffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        if status == .error || error != nil {
            return nil
        }
        return outputBuffer
    }

    private func createStereoBuffer(fromMono monoBuffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let monoData = monoBuffer.floatChannelData?[0],
              let stereoBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: monoBuffer.frameLength) else {
            return nil
        }
        stereoBuffer.frameLength = monoBuffer.frameLength
        if let left = stereoBuffer.floatChannelData?[0], let right = stereoBuffer.floatChannelData?[1] {
            memcpy(left, monoData, Int(monoBuffer.frameLength) * MemoryLayout<Float>.size)
            memcpy(right, monoData, Int(monoBuffer.frameLength) * MemoryLayout<Float>.size)
        }
        return stereoBuffer
    }

    // MARK: - Dynamic Input Tap Management

    public func installInputTapSafely() {
        guard !isTapInstalled else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            return
        }

        DispatchQueue.main.async {
            self.inputChannelCount = Int(format.channelCount)
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, _ in
            // Forward input buffer to DSP anti-noise processor
            _ = VDSPAntiNoiseProcessor.shared.processInputBuffer(buffer)

            // Forward to VU meter and noise gate
            ProMicEngine.shared.processMicrophoneBuffer(buffer)

            // Forward to latency calibrator if active
            if AutoLatencyCalibrator.shared.isCalibrating,
               let channel = buffer.floatChannelData?[0] {
                AutoLatencyCalibrator.shared.appendMicrophoneSamples(channel, count: Int(buffer.frameLength))
            }
        }

        isTapInstalled = true
        ProMicEngine.shared.configureVoiceProcessing(on: inputNode)
    }

    public func removeInputTapSafely() {
        guard isTapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    // MARK: - Route Change & Interruption Handling

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            self.removeInputTapSafely()

            do {
                try self.configureAudioSession(forceEarbudMic: self.isUsingEarbudMic)
                if self.engine.isRunning {
                    self.installInputTapSafely()
                }
            } catch {
                print("Error handling audio route change: \(error)")
            }
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            engineQueue.async { [weak self] in
                try? self?.startEngine()
            }
        }
    }
}

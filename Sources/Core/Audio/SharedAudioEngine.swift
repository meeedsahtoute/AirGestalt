//
//  SharedAudioEngine.swift
//  AirGestalt
//
//  Single Shared AVAudioEngine & Resilient Audio Session Coordinator.
//  Protects against format and channel-count mismatches, handles route changes dynamically,
//  integrates 10-band parametric EQ, zero-latency software transparency,
//  and provides converter-backed safe buffer scheduling.
//

import Foundation
import AVFoundation
import Combine

public final class SharedAudioEngine: ObservableObject {
    public static let shared = SharedAudioEngine()

    public let engine = AVAudioEngine()
    public let playerNode = AVAudioPlayerNode()
    public let eqNode = AVAudioUnitEQ(numberOfBands: 10)
    public let transparencyMixer = AVAudioMixerNode()
    public let mainMixer: AVAudioMixerNode

    @Published public var isRunning: Bool = false
    @Published public var currentInputSampleRate: Double = 48000.0
    @Published public var preferredMicPort: String = "Built-In Microphone"
    @Published public var activeOutputDeviceName: String = "Built-In Speaker"
    @Published public var isUsingEarbudMic: Bool = false
    @Published public var inputChannelCount: Int = 1
    @Published public var isSoftwareTransparencyActive: Bool = false
    @Published public var isAmbientMonitoringActive: Bool = false
    @Published public var transparencyGain: Float = 1.0

    private var isTapInstalled: Bool = false
    private let engineQueue = DispatchQueue(label: "com.airgestalt.audioengine.queue", qos: .userInitiated)

    public static let canonicalFormat = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 2)

    private init() {
        self.mainMixer = engine.mainMixerNode

        // Attach audio processing nodes to engine graph
        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.attach(transparencyMixer)

        // Initialize transparency mixer to muted by default
        transparencyMixer.outputVolume = 0.0

        // Wire playback chain: playerNode -> eqNode -> mainMixer
        wirePlaybackNodes()

        // Wire transparency chain: transparencyMixer -> mainMixer
        if let canonical = SharedAudioEngine.canonicalFormat {
            engine.connect(transparencyMixer, to: mainMixer, format: canonical)
        } else {
            engine.connect(transparencyMixer, to: mainMixer, format: nil)
        }

        setupNotificationObservers()
        updateActiveRoute()
    }

    private func wirePlaybackNodes() {
        if let canonical = SharedAudioEngine.canonicalFormat {
            engine.connect(playerNode, to: eqNode, format: canonical)
            engine.connect(eqNode, to: mainMixer, format: canonical)
        } else {
            engine.connect(playerNode, to: eqNode, format: nil)
            engine.connect(eqNode, to: mainMixer, format: nil)
        }
    }

    // MARK: - Safe Audio Session Configuration

    public func configureAudioSession(forceEarbudMic: Bool = false) throws {
        let session = AVAudioSession.sharedInstance()
        self.isUsingEarbudMic = forceEarbudMic

        // Non-interrupting mixing options:
        // Strictly avoid .allowBluetooth (which forces HFP 16kHz call mode and pauses background music)
        // unless forceEarbudMic is explicitly requested.
        var sessionOptions: AVAudioSession.CategoryOptions = [
            .mixWithOthers,
            .allowBluetoothA2DP,
            .defaultToSpeaker
        ]

        if forceEarbudMic {
            sessionOptions.insert(.allowBluetooth)
        }

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
        try? session.setPreferredIOBufferDuration(0.00533) // Ultra-low latency ~5.3ms
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        updateActiveRoute()

        DispatchQueue.main.async {
            self.currentInputSampleRate = session.sampleRate
        }
    }

    public func updateActiveRoute() {
        let session = AVAudioSession.sharedInstance()
        let portName = session.currentRoute.outputs.first?.portName ?? "Built-In Speaker"
        DispatchQueue.main.async {
            self.activeOutputDeviceName = portName
        }
    }

    // MARK: - Engine Lifecycle

    public func startEngine() throws {
        guard !engine.isRunning else { return }

        try configureAudioSession(forceEarbudMic: isUsingEarbudMic)

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
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            if self.engine.isRunning {
                self.removeInputTapSafely()
                self.playerNode.stop()
                self.engine.stop()
            }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            DispatchQueue.main.async {
                self.isRunning = false
                self.isSoftwareTransparencyActive = false
                self.isAmbientMonitoringActive = false
                VDSPAntiNoiseProcessor.shared.ambientSPLdB = 0.0
                VDSPAntiNoiseProcessor.shared.frequencySpectrum = Array(repeating: 0.0, count: 24)
            }
        }
    }

    private func ensureNodesConnected() {
        let targetFormat = playerNode.outputFormat(forBus: 0)
        if targetFormat.channelCount == 0 || targetFormat.sampleRate == 0 {
            wirePlaybackNodes()
        }

        // Check and safely wire inputNode to transparencyMixer
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        if inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 {
            engine.disconnectNodeOutput(inputNode)
            engine.connect(inputNode, to: transparencyMixer, format: inputFormat)
        }
    }

    // MARK: - Real Software Low-Latency Transparency

    public func setTransparencyActive(_ active: Bool, gain: Float = 1.0) {
        let safeGain = max(0.0, min(1.5, gain))
        self.isSoftwareTransparencyActive = active
        self.transparencyGain = safeGain

        engineQueue.async { [weak self] in
            guard let self = self else { return }

            if active {
                if !self.engine.isRunning {
                    do {
                        try self.startEngine()
                    } catch {
                        print("SharedAudioEngine: Failed to start for transparency: \(error)")
                    }
                }
                self.ensureNodesConnected()
                self.transparencyMixer.outputVolume = safeGain
            } else {
                self.transparencyMixer.outputVolume = 0.0
                if !self.isAmbientMonitoringActive {
                    self.stopEngine()
                }
            }

            DispatchQueue.main.async {
                self.isSoftwareTransparencyActive = active
            }
        }
    }

    // MARK: - Ambient dB Monitoring

    public func setAmbientMonitoringActive(_ active: Bool) {
        self.isAmbientMonitoringActive = active
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            if active {
                if !self.engine.isRunning {
                    do {
                        try self.startEngine()
                    } catch {
                        print("Failed to start engine for ambient monitoring: \(error)")
                    }
                }
            } else {
                if !self.isSoftwareTransparencyActive {
                    self.stopEngine()
                }
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

            // 2. Hardware channel mismatch conversion (Mono to Stereo or Rate Conversion)
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

            // Forward to ear tip fit test if active
            if SpatialDSPEngine.shared.isRunningFitTest {
                SpatialDSPEngine.shared.appendFitTestBuffer(buffer)
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
        updateActiveRoute()
        guard engine.isRunning else { return }
        engineQueue.async { [weak self] in
            guard let self = self, self.engine.isRunning else { return }
            self.removeInputTapSafely()

            do {
                try self.configureAudioSession(forceEarbudMic: self.isUsingEarbudMic)
                if self.engine.isRunning {
                    self.ensureNodesConnected()
                    self.installInputTapSafely()
                }
            } catch {
                print("Error handling audio route change: \(error)")
            }
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard engine.isRunning else { return }
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            engineQueue.async { [weak self] in
                guard let self = self, self.isRunning else { return }
                try? self.startEngine()
            }
        }
    }
}

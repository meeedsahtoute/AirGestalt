//
//  SharedAudioEngine.swift
//  AirGestalt
//
//  Single Shared On-Demand AVAudioEngine & Resilient Audio Session Coordinator.
//  100% Strictly Lazy: Zero audio session or hardware initialization on app launch or tab switching.
//  Preserves background music (Spotify / Apple Music) in pristine A2DP stereo fidelity.
//

import Foundation
import AVFoundation
import Combine

public final class SharedAudioEngine: ObservableObject {
    public static let shared = SharedAudioEngine()

    // Strictly lazy audio engine & nodes (nil when inactive)
    public var engine: AVAudioEngine?
    public var playerNode: AVAudioPlayerNode?
    public var eqNode: AVAudioUnitEQ?
    public var transparencyMixer: AVAudioMixerNode?

    @Published public var isRunning: Bool = false
    @Published public var currentInputSampleRate: Double = 48000.0
    @Published public var preferredMicPort: String = "Built-In Microphone"
    @Published public var activeOutputDeviceName: String = "AirPods Pro"
    @Published public var isUsingEarbudMic: Bool = false
    @Published public var inputChannelCount: Int = 1
    @Published public var isSoftwareTransparencyActive: Bool = false
    @Published public var isAmbientMonitoringActive: Bool = false
    @Published public var transparencyGain: Float = 1.0

    private var isTapInstalled: Bool = false
    private let engineQueue = DispatchQueue(label: "com.airgestalt.audioengine.queue", qos: .userInitiated)

    public static let canonicalFormat = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 2)

    private init() {
        // Zero audio hardware or session interaction on launch.
        setupNotificationObservers()
    }

    // MARK: - Safe Audio Session Configuration (Strictly On-Demand)

    public func configureAudioSession(forceEarbudMic: Bool = false) throws {
        let session = AVAudioSession.sharedInstance()
        self.isUsingEarbudMic = forceEarbudMic

        // Non-interrupting mixing options:
        // Strictly avoid .allowBluetooth (which forces HFP 16kHz call mode and pauses background music)
        // unless forceEarbudMic is explicitly requested for earbud mic passthrough.
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
        guard isRunning else {
            DispatchQueue.main.async {
                if let name = CloneGATTClient.shared.connectedPeripheralName {
                    self.activeOutputDeviceName = name
                } else {
                    self.activeOutputDeviceName = "AirPods Pro"
                }
            }
            return
        }

        let session = AVAudioSession.sharedInstance()
        let portName = session.currentRoute.outputs.first?.portName ?? "AirPods Pro"
        DispatchQueue.main.async {
            self.activeOutputDeviceName = portName
        }
    }

    // MARK: - On-Demand Engine Lifecycle

    public func startEngine(forceEarbudMic: Bool = false) throws {
        guard !isRunning else { return }

        // 1. Configure audio session FIRST with non-interrupting mixing options
        try configureAudioSession(forceEarbudMic: forceEarbudMic)

        // 2. Lazily instantiate audio engine and nodes
        let newEngine = AVAudioEngine()
        let newPlayer = AVAudioPlayerNode()
        let newEQ = AVAudioUnitEQ(numberOfBands: 10)
        let newTransparencyMixer = AVAudioMixerNode()

        self.engine = newEngine
        self.playerNode = newPlayer
        self.eqNode = newEQ
        self.transparencyMixer = newTransparencyMixer

        // Apply 10-band EQ frequencies & gains
        setup10BandEQ(on: newEQ)

        // Attach nodes to graph
        newEngine.attach(newPlayer)
        newEngine.attach(newEQ)
        newEngine.attach(newTransparencyMixer)

        newTransparencyMixer.outputVolume = isSoftwareTransparencyActive ? transparencyGain : 0.0

        let mainMixer = newEngine.mainMixerNode
        if let canonical = SharedAudioEngine.canonicalFormat {
            newEngine.connect(newPlayer, to: newEQ, format: canonical)
            newEngine.connect(newEQ, to: mainMixer, format: canonical)
            newEngine.connect(newTransparencyMixer, to: mainMixer, format: canonical)
        } else {
            newEngine.connect(newPlayer, to: newEQ, format: nil)
            newEngine.connect(newEQ, to: mainMixer, format: nil)
            newEngine.connect(newTransparencyMixer, to: mainMixer, format: nil)
        }

        // Connect inputNode to transparency mixer safely
        let inputNode = newEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        if inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 {
            newEngine.connect(inputNode, to: newTransparencyMixer, format: inputFormat)
        }

        // 3. Start engine and player
        try newEngine.start()
        newPlayer.play()

        installInputTapSafely()

        DispatchQueue.main.async {
            self.isRunning = true
        }
    }

    public func stopEngine() {
        engineQueue.async { [weak self] in
            guard let self = self else { return }

            if let engine = self.engine {
                self.removeInputTapSafely()
                self.playerNode?.stop()
                engine.stop()
                self.engine = nil
                self.playerNode = nil
                self.eqNode = nil
                self.transparencyMixer = nil
            }

            // Clean Deactivation: Tell iOS to restore full priority to background music apps
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

    private func setup10BandEQ(on eq: AVAudioUnitEQ) {
        let currentGains = SpatialDSPEngine.shared.currentGains
        for (index, freq) in SpatialDSPEngine.isoFrequencies.enumerated() {
            guard index < eq.bands.count else { break }
            let band = eq.bands[index]
            band.frequency = freq
            band.bandwidth = 1.0 // 1 octave
            band.filterType = .parametric
            band.bypass = false
            band.gain = (index < currentGains.count) ? currentGains[index] : 0.0
        }
    }

    // MARK: - On-Demand Software Transparency

    public func setTransparencyActive(_ active: Bool, gain: Float = 1.0) {
        let safeGain = max(0.0, min(1.5, gain))
        self.isSoftwareTransparencyActive = active
        self.transparencyGain = safeGain

        engineQueue.async { [weak self] in
            guard let self = self else { return }

            if active {
                if !self.isRunning || self.engine == nil {
                    do {
                        try self.startEngine(forceEarbudMic: self.isUsingEarbudMic)
                    } catch {
                        print("SharedAudioEngine: Failed to start for transparency: \(error)")
                    }
                }
                self.transparencyMixer?.outputVolume = safeGain
            } else {
                self.transparencyMixer?.outputVolume = 0.0
                if !self.isAmbientMonitoringActive {
                    self.stopEngine()
                }
            }

            DispatchQueue.main.async {
                self.isSoftwareTransparencyActive = active
            }
        }
    }

    // MARK: - On-Demand Ambient dB Monitoring

    public func setAmbientMonitoringActive(_ active: Bool) {
        self.isAmbientMonitoringActive = active
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            if active {
                if !self.isRunning || self.engine == nil {
                    do {
                        try self.startEngine(forceEarbudMic: self.isUsingEarbudMic)
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

            if !self.isRunning || self.engine == nil {
                do {
                    try self.startEngine(forceEarbudMic: self.isUsingEarbudMic)
                } catch {
                    print("SharedAudioEngine start error: \(error)")
                    return
                }
            }

            guard let player = self.playerNode, let engine = self.engine, engine.isRunning else { return }

            let outputFormat = player.outputFormat(forBus: 0)
            guard outputFormat.channelCount > 0, outputFormat.sampleRate > 0 else { return }

            // 1. Direct match
            if buffer.format.channelCount == outputFormat.channelCount &&
               abs(buffer.format.sampleRate - outputFormat.sampleRate) < 1.0 {
                player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
                if !player.isPlaying { player.play() }
                return
            }

            // 2. Hardware channel mismatch conversion (Mono to Stereo or Rate Conversion)
            if let converted = self.convertBuffer(buffer, to: outputFormat) {
                player.scheduleBuffer(converted, at: nil, options: [], completionHandler: nil)
                if !player.isPlaying { player.play() }
                return
            }

            // 3. Fallback stereo channel duplication
            if outputFormat.channelCount == 2 && buffer.format.channelCount == 1 {
                if let stereo = self.createStereoBuffer(fromMono: buffer, targetFormat: outputFormat) {
                    player.scheduleBuffer(stereo, at: nil, options: [], completionHandler: nil)
                    if !player.isPlaying { player.play() }
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
        guard let engine = self.engine, !isTapInstalled else { return }

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
        guard isTapInstalled, let engine = self.engine else { return }
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
        guard engine?.isRunning == true else { return }
        engineQueue.async { [weak self] in
            guard let self = self, self.engine?.isRunning == true else { return }
            self.removeInputTapSafely()

            do {
                try self.configureAudioSession(forceEarbudMic: self.isUsingEarbudMic)
                if self.engine?.isRunning == true {
                    self.installInputTapSafely()
                }
            } catch {
                print("Error handling audio route change: \(error)")
            }
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard engine?.isRunning == true else { return }
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            engineQueue.async { [weak self] in
                guard let self = self, self.isRunning else { return }
                try? self.startEngine(forceEarbudMic: self.isUsingEarbudMic)
            }
        }
    }
}

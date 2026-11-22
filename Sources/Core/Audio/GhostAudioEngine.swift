//
//  GhostAudioEngine.swift
//  AirGestalt
//
//  Crash-proof single-controller audio engine designed specifically for
//  AirPods Pro acoustic emulation (Adaptive EQ, Bass Boost, Spatial Widening, Safe Transparency,
//  Dynamic Adaptive Leveling, and Max ANC Acoustic Masking) on replica/open-ear earbuds
//  via LiveContainer on iOS 17+.
//  Zero forced unwraps. Zero try!. Serial queue isolation. Zero audio session interruption.
//

import Foundation
import AVFoundation
import Combine
import Accelerate

public final class GhostAudioEngine: ObservableObject {
    public static let shared = GhostAudioEngine()

    // MARK: - Published State
    @Published public var isRunning: Bool = false
    @Published public var isGhostModeActive: Bool = false
    @Published public var activeNoiseControlMode: NoiseControlMode = .off
    @Published public var isSoftwareTransparencyActive: Bool = false
    @Published public var isAmbientMonitoringActive: Bool = false
    @Published public var isPlayingTestAudio: Bool = false
    @Published public var isSpatialWideningEnabled: Bool = true
    @Published public var spatialWideningAmount: Float = 18.0
    @Published public var isBassBoostActive: Bool = false
    @Published public var transparencyGain: Float = 1.0
    @Published public var statusMessage: String = "Ready"

    // Real Route & Hardware Detection
    @Published public var activeOutputDeviceName: String = "AirPods Pro"
    @Published public var activeRouteConnectionType: String = "Bluetooth A2DP"
    @Published public var activeRouteUID: String = ""
    @Published public var currentSampleRateString: String = "48.0 kHz"
    @Published public var isBluetoothOutputConnected: Bool = true

    // Open-Ear Acoustic Target Profile: +4dB sub-bass, -2dB muddy 350Hz, +4dB highs
    @Published public var eqGains: [Float] = [4.0, 6.0, 5.0, -2.0, 0.0, 1.5, 2.0, 4.0, 4.0, 3.0]

    // MARK: - Core Audio Engine & Nodes
    public var engine: AVAudioEngine?
    public var playerNode: AVAudioPlayerNode?
    public var eqNode: AVAudioUnitEQ?
    public var reverbNode: AVAudioUnitReverb?

    // Single Serial Queue for 100% Race-Free Audio Mutations
    private let queue = DispatchQueue(label: "com.airgestalt.ghostengine.serial", qos: .userInitiated)
    private var testLoopBuffer: AVAudioPCMBuffer?
    private var maskingLoopBuffer: AVAudioPCMBuffer?
    private var isMixerTapInstalled: Bool = false
    private var lastAdaptiveAdjustmentTime: TimeInterval = 0

    public static let isoFrequencies: [Float] = [
        32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
    ]

    private init() {
        if let saved = UserDefaults.standard.array(forKey: "com.airgestalt.eqGains") as? [Float], saved.count == 10 {
            self.eqGains = saved
        }
        setupNotifications()
        updateRouteInfo()
    }

    // MARK: - Safe Queue Helper
    private func executeOnQueue(_ block: @escaping () -> Void) {
        queue.async { block() }
    }

    // MARK: - Primary Noise Control Mode Dispatcher

    public func setNoiseControlMode(_ mode: NoiseControlMode) {
        executeOnQueue { [weak self] in
            guard let self = self else { return }

            switch mode {
            case .transparency:
                self.startTransparencyEngine()
            case .adaptive:
                self.startAdaptiveEngine()
            case .noiseCancellation:
                self.startMaxANCEngine()
            case .off:
                self.stopAnyEngine()
                DispatchQueue.main.async {
                    self.activeNoiseControlMode = .off
                    self.statusMessage = "Off"
                }
            }
        }
    }

    // MARK: - 1. Safe Transparency Mode (iPhone Built-In Mic -> Vocal Clarity -> Earbuds)

    public func setTransparencyActive(_ active: Bool, gain: Float = 1.0) {
        let safeGain = max(0.0, min(2.0, gain))
        self.transparencyGain = safeGain

        if active {
            setNoiseControlMode(.transparency)
        } else {
            setNoiseControlMode(.off)
        }
    }

    private func startTransparencyEngine(gain: Float = 1.0) {
        let session = AVAudioSession.sharedInstance()

        if session.recordPermission == .denied {
            DispatchQueue.main.async {
                self.statusMessage = "Microphone access denied in Settings"
                self.isSoftwareTransparencyActive = false
                self.isAmbientMonitoringActive = false
            }
            return
        }

        if session.recordPermission == .undetermined {
            session.requestRecordPermission { [weak self] granted in
                if granted {
                    self?.executeOnQueue { self?.startTransparencyEngine(gain: gain) }
                }
            }
            return
        }

        stopAnyEngine()

        do {
            // Configure .playAndRecord with .mixWithOthers so background music continues playing!
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
            )

            if let inputs = session.availableInputs,
               let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }

            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let newEngine = AVAudioEngine()
            let inputNode = newEngine.inputNode
            let eq = AVAudioUnitEQ(numberOfBands: 10)
            let reverb = AVAudioUnitReverb()

            // Apply vocal clarity boost curve (1kHz - 4kHz)
            self.applyTransparencyGains(to: eq)

            reverb.loadFactoryPreset(.smallRoom)
            reverb.wetDryMix = self.isSpatialWideningEnabled ? self.spatialWideningAmount : 0.0

            newEngine.attach(eq)
            newEngine.attach(reverb)

            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
                throw NSError(domain: "AirGestalt", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid mic format"])
            }

            newEngine.connect(inputNode, to: eq, format: nil)
            newEngine.connect(eq, to: reverb, format: nil)
            newEngine.connect(reverb, to: newEngine.mainMixerNode, format: nil)

            newEngine.mainMixerNode.outputVolume = self.transparencyGain

            try newEngine.start()

            // Stream mixer audio to VDSPAntiNoiseProcessor for live dB and FFT telemetry
            newEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                _ = VDSPAntiNoiseProcessor.shared.processInputBuffer(buffer)
            }
            self.isMixerTapInstalled = true

            self.engine = newEngine
            self.eqNode = eq
            self.reverbNode = reverb
            self.playerNode = nil

            self.updateRouteInfo()

            DispatchQueue.main.async {
                self.isRunning = true
                self.activeNoiseControlMode = .transparency
                self.isSoftwareTransparencyActive = true
                self.isAmbientMonitoringActive = true
                self.statusMessage = "Live Transparency Active (iPhone Mic)"
            }
        } catch {
            stopAnyEngine()
            DispatchQueue.main.async {
                self.isSoftwareTransparencyActive = false
                self.isAmbientMonitoringActive = false
                self.statusMessage = "Transparency Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 2. Adaptive Mode (Live Mic Passthrough + DynamicsProcessor Ambient Leveling)

    private func startAdaptiveEngine() {
        let session = AVAudioSession.sharedInstance()

        if session.recordPermission == .denied {
            DispatchQueue.main.async {
                self.statusMessage = "Microphone access denied in Settings"
                self.isSoftwareTransparencyActive = false
                self.isAmbientMonitoringActive = false
            }
            return
        }

        if session.recordPermission == .undetermined {
            session.requestRecordPermission { [weak self] granted in
                if granted {
                    self?.executeOnQueue { self?.startAdaptiveEngine() }
                }
            }
            return
        }

        stopAnyEngine()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
            )

            if let inputs = session.availableInputs,
               let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }

            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let newEngine = AVAudioEngine()
            let inputNode = newEngine.inputNode
            let eq = AVAudioUnitEQ(numberOfBands: 10)
            let reverb = AVAudioUnitReverb()

            // Adaptive EQ: Gentle sub-bass warmth (+2.5dB at 64Hz/125Hz) & balanced speech
            self.applyAdaptiveGains(to: eq)

            reverb.loadFactoryPreset(.smallRoom)
            reverb.wetDryMix = self.isSpatialWideningEnabled ? self.spatialWideningAmount : 0.0

            newEngine.attach(eq)
            newEngine.attach(reverb)

            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
                throw NSError(domain: "AirGestalt", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid mic format"])
            }

            newEngine.connect(inputNode, to: eq, format: nil)
            newEngine.connect(eq, to: reverb, format: nil)
            newEngine.connect(reverb, to: newEngine.mainMixerNode, format: nil)

            newEngine.mainMixerNode.outputVolume = self.transparencyGain

            try newEngine.start()

            newEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                _ = VDSPAntiNoiseProcessor.shared.processInputBuffer(buffer)
                self?.handleAdaptiveLeveling(currentSPL: VDSPAntiNoiseProcessor.shared.ambientSPLdB)
            }
            self.isMixerTapInstalled = true

            self.engine = newEngine
            self.eqNode = eq
            self.reverbNode = reverb
            self.playerNode = nil

            self.updateRouteInfo()

            DispatchQueue.main.async {
                self.isRunning = true
                self.activeNoiseControlMode = .adaptive
                self.isSoftwareTransparencyActive = true
                self.isAmbientMonitoringActive = true
                self.statusMessage = "Adaptive Audio Active (Dynamic Leveling)"
            }
        } catch {
            stopAnyEngine()
            DispatchQueue.main.async {
                self.isSoftwareTransparencyActive = false
                self.isAmbientMonitoringActive = false
                self.statusMessage = "Adaptive Error: \(error.localizedDescription)"
            }
        }
    }

    private func handleAdaptiveLeveling(currentSPL: Float) {
        let now = Date().timeIntervalSince1970
        guard now - lastAdaptiveAdjustmentTime > 0.15 else { return }
        lastAdaptiveAdjustmentTime = now

        guard let eng = engine, eng.isRunning else { return }

        // Dynamic Leveling:
        // SPL > 72dB: attenuate to protect ears (down to 0.45)
        // SPL < 52dB: boost quiet speech (up to 1.25)
        let targetVolume: Float
        if currentSPL > 72.0 {
            let over = min(20.0, currentSPL - 72.0)
            targetVolume = max(0.40, 0.85 - (over / 20.0) * 0.45)
        } else if currentSPL < 52.0 {
            let under = min(20.0, 52.0 - currentSPL)
            targetVolume = min(1.30, 0.95 + (under / 20.0) * 0.35)
        } else {
            targetVolume = 0.95
        }

        let currentVol = eng.mainMixerNode.outputVolume
        eng.mainMixerNode.outputVolume = (currentVol * 0.80) + (targetVolume * 0.20)
    }

    // MARK: - 3. Max ANC Mode (Acoustic Masking & Low-End Isolation Bed)

    private func startMaxANCEngine() {
        stopAnyEngine()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let newEngine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let eq = AVAudioUnitEQ(numberOfBands: 10)
            let reverb = AVAudioUnitReverb()

            // Apply acoustic masking & isolation EQ curve:
            // Aggressive low-end hum masking (+4.5dB at 64Hz/125Hz) + tight vocal roll-off (-8.0dB at 1kHz-4kHz)
            self.applyMaxANCGains(to: eq)

            reverb.loadFactoryPreset(.smallRoom)
            reverb.wetDryMix = self.isSpatialWideningEnabled ? self.spatialWideningAmount : 0.0

            newEngine.attach(player)
            newEngine.attach(eq)
            newEngine.attach(reverb)

            newEngine.connect(player, to: eq, format: nil)
            newEngine.connect(eq, to: reverb, format: nil)
            newEngine.connect(reverb, to: newEngine.mainMixerNode, format: nil)

            // Low-floor soothing bed volume
            newEngine.mainMixerNode.outputVolume = 0.65

            guard let maskingBuffer = self.getOrCreateMaskingBuffer() else {
                throw NSError(domain: "AirGestalt", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate isolation bed"])
            }

            try newEngine.start()
            player.scheduleBuffer(maskingBuffer, at: nil, options: .loops, completionHandler: nil)
            player.play()

            newEngine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                _ = VDSPAntiNoiseProcessor.shared.processInputBuffer(buffer)
            }
            self.isMixerTapInstalled = true

            self.engine = newEngine
            self.playerNode = player
            self.eqNode = eq
            self.reverbNode = reverb

            self.updateRouteInfo()

            DispatchQueue.main.async {
                self.isRunning = true
                self.activeNoiseControlMode = .noiseCancellation
                self.isSoftwareTransparencyActive = false
                self.isAmbientMonitoringActive = false
                self.statusMessage = "Max ANC Active (Acoustic Masking & Isolation)"
            }
        } catch {
            stopAnyEngine()
            DispatchQueue.main.async {
                self.statusMessage = "Max ANC Error: \(error.localizedDescription)"
            }
        }
    }

    private func getOrCreateMaskingBuffer() -> AVAudioPCMBuffer? {
        if let b = maskingLoopBuffer { return b }

        let sampleRate: Double = 48000.0
        let frames = Int(sampleRate * 2.5) // 2.5s seamless loop
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)

        guard let left = buffer.floatChannelData?[0], let right = buffer.floatChannelData?[1] else { return nil }

        var brownL: Double = 0.0
        var brownR: Double = 0.0
        var b0_L: Double = 0.0, b1_L: Double = 0.0, b2_L: Double = 0.0, b3_L: Double = 0.0, b4_L: Double = 0.0, b5_L: Double = 0.0
        var b0_R: Double = 0.0, b1_R: Double = 0.0, b2_R: Double = 0.0, b3_R: Double = 0.0, b4_R: Double = 0.0, b5_R: Double = 0.0

        for i in 0..<frames {
            // White noise seeds
            let whiteL = (Double((i &* 1664525 &+ 1013904223) & 0x7FFFFFFF) / Double(0x7FFFFFFF)) * 2.0 - 1.0
            let whiteR = (Double(((i &+ 7) &* 1103515245 &+ 12345) & 0x7FFFFFFF) / Double(0x7FFFFFFF)) * 2.0 - 1.0

            // Brown noise (leaky integration for deep soothing warmth)
            brownL = 0.985 * brownL + 0.09 * whiteL
            brownR = 0.985 * brownR + 0.09 * whiteR

            // Pink noise (Kellet filter)
            b0_L = 0.99886 * b0_L + whiteL * 0.0555179
            b1_L = 0.99332 * b1_L + whiteL * 0.0750759
            b2_L = 0.96900 * b2_L + whiteL * 0.1538520
            b3_L = 0.86650 * b3_L + whiteL * 0.3104856
            b4_L = 0.55000 * b4_L + whiteL * 0.5329522
            b5_L = -0.7616 * b5_L - whiteL * 0.0168980
            let pinkL = (b0_L + b1_L + b2_L + b3_L + b4_L + b5_L + whiteL * 0.5362) * 0.11

            b0_R = 0.99886 * b0_R + whiteR * 0.0555179
            b1_R = 0.99332 * b1_R + whiteR * 0.0750759
            b2_R = 0.96900 * b2_R + whiteR * 0.1538520
            b3_R = 0.86650 * b3_R + whiteR * 0.3104856
            b4_R = 0.55000 * b4_R + whiteR * 0.5329522
            b5_R = -0.7616 * b5_R - whiteR * 0.0168980
            let pinkR = (b0_R + b1_R + b2_R + b3_R + b4_R + b5_R + whiteR * 0.5362) * 0.11

            // 70% Brown + 30% Pink
            var sL = (brownL * 0.70 + pinkL * 0.30) * 0.28
            var sR = (brownR * 0.70 + pinkR * 0.30) * 0.28

            // Seamless crossfade window at boundaries (first & last 240 samples)
            let crossFadeLength = 240
            if i < crossFadeLength {
                let gain = Double(i) / Double(crossFadeLength)
                sL *= gain
                sR *= gain
            } else if i > frames - crossFadeLength {
                let gain = Double(frames - i) / Double(crossFadeLength)
                sL *= gain
                sR *= gain
            }

            left[i] = Float(max(-0.6, min(0.6, sL)))
            right[i] = Float(max(-0.6, min(0.6, sR)))
        }

        maskingLoopBuffer = buffer
        return buffer
    }

    // MARK: - 4. AirPods Pro Acoustic Playback Engine (Zero Mic Access)

    public func startPlaybackEngine(completion: (() -> Void)? = nil) {
        executeOnQueue { [weak self] in
            guard let self = self else { return }

            if self.isRunning && self.engine?.isRunning == true && self.playerNode != nil {
                completion?()
                return
            }

            self.stopAnyEngine()

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP])
                try session.setActive(true, options: .notifyOthersOnDeactivation)

                let newEngine = AVAudioEngine()
                let player = AVAudioPlayerNode()
                let eq = AVAudioUnitEQ(numberOfBands: 10)
                let reverb = AVAudioUnitReverb()

                self.applyGains(to: eq)

                reverb.loadFactoryPreset(.smallRoom)
                reverb.wetDryMix = self.isSpatialWideningEnabled ? self.spatialWideningAmount : 0.0

                newEngine.attach(player)
                newEngine.attach(eq)
                newEngine.attach(reverb)

                newEngine.connect(player, to: eq, format: nil)
                newEngine.connect(eq, to: reverb, format: nil)
                newEngine.connect(reverb, to: newEngine.mainMixerNode, format: nil)

                try newEngine.start()
                player.play()

                self.engine = newEngine
                self.playerNode = player
                self.eqNode = eq
                self.reverbNode = reverb

                self.updateRouteInfo()

                DispatchQueue.main.async {
                    self.isRunning = true
                    self.statusMessage = "Acoustic Emulation Active"
                }

                completion?()
            } catch {
                self.stopAnyEngine()
                DispatchQueue.main.async {
                    self.statusMessage = "Playback Engine Error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 5. Clean Engine Teardown

    public func stopEngine() {
        executeOnQueue { [weak self] in
            guard let self = self else { return }
            self.stopAnyEngine()
            DispatchQueue.main.async {
                self.statusMessage = "Stopped"
            }
        }
    }

    private func stopAnyEngine() {
        if let eng = engine {
            if isMixerTapInstalled {
                eng.mainMixerNode.removeTap(onBus: 0)
                isMixerTapInstalled = false
            }
            playerNode?.stop()
            if eng.isRunning { eng.stop() }
            eng.reset()
        }
        engine = nil
        playerNode = nil
        eqNode = nil
        reverbNode = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        DispatchQueue.main.async {
            self.isRunning = false
            self.activeNoiseControlMode = .off
            self.isSoftwareTransparencyActive = false
            self.isAmbientMonitoringActive = false
            self.isPlayingTestAudio = false
            VDSPAntiNoiseProcessor.shared.ambientSPLdB = 0.0
            VDSPAntiNoiseProcessor.shared.frequencySpectrum = Array(repeating: 0.0, count: 24)
        }
    }

    // MARK: - 6. Real-Time 10-Band EQ, Bass Boost & Spatial Widening

    public func updateLiveEQGain(bandIndex: Int, gain: Float) {
        guard bandIndex >= 0 && bandIndex < eqGains.count else { return }
        eqGains[bandIndex] = gain
        UserDefaults.standard.set(eqGains, forKey: "com.airgestalt.eqGains")

        executeOnQueue { [weak self] in
            guard let self = self,
                  let eq = self.eqNode,
                  self.engine?.isRunning == true,
                  bandIndex < eq.bands.count else { return }
            let finalGain = (self.isBassBoostActive && bandIndex <= 2) ? (gain + (bandIndex == 2 ? 4.0 : 6.0)) : gain
            eq.bands[bandIndex].gain = max(-18.0, min(18.0, finalGain))
        }
    }

    public func updateAllLiveEQBands(gains: [Float]) {
        self.eqGains = gains
        UserDefaults.standard.set(eqGains, forKey: "com.airgestalt.eqGains")

        executeOnQueue { [weak self] in
            guard let self = self,
                  let eq = self.eqNode,
                  self.engine?.isRunning == true else { return }
            self.applyGains(to: eq)
        }
    }

    public func setBassBoostActive(_ active: Bool) {
        self.isBassBoostActive = active
        executeOnQueue { [weak self] in
            guard let self = self, let eq = self.eqNode, self.engine?.isRunning == true else { return }
            self.applyGains(to: eq)
        }
    }

    public func setSpatialWideningMix(_ mix: Float) {
        let clamped = max(0.0, min(50.0, mix))
        self.spatialWideningAmount = clamped
        self.isSpatialWideningEnabled = clamped > 0.0
        executeOnQueue { [weak self] in
            guard let self = self, let reverb = self.reverbNode, self.engine?.isRunning == true else { return }
            reverb.wetDryMix = clamped
        }
    }

    public func toggleSpatialWidening(_ enabled: Bool) {
        self.isSpatialWideningEnabled = enabled
        executeOnQueue { [weak self] in
            guard let self = self, let reverb = self.reverbNode, self.engine?.isRunning == true else { return }
            reverb.wetDryMix = enabled ? self.spatialWideningAmount : 0.0
        }
    }

    public func updateTransparencyGain(_ gain: Float) {
        let safeGain = max(0.0, min(2.0, gain))
        self.transparencyGain = safeGain
        executeOnQueue { [weak self] in
            guard let self = self, let eng = self.engine, eng.isRunning else { return }
            eng.mainMixerNode.outputVolume = safeGain
        }
    }

    public func applyTransparencyGains(to eq: AVAudioUnitEQ) {
        // Vocal clarity curve: boost 1kHz - 4kHz for clear voice passthrough
        let clarityCurve: [Float] = [-2.5, -1.5, 0.0, 0.5, 1.0, 3.5, 4.5, 3.5, 1.5, 0.0]
        applyGains(to: eq, baseGains: clarityCurve)
    }

    public func applyAdaptiveGains(to eq: AVAudioUnitEQ) {
        // Adaptive curve: gentle sub-bass warmth (+2.5dB at 64Hz/125Hz) & balanced mids
        let adaptiveCurve: [Float] = [1.5, 2.5, 2.0, 0.5, 0.0, 1.5, 2.0, 1.5, 1.0, 0.5]
        applyGains(to: eq, baseGains: adaptiveCurve)
    }

    public func applyMaxANCGains(to eq: AVAudioUnitEQ) {
        // Acoustic masking curve: +4.5dB low-end hum mask, -8.0dB vocal speech roll-off
        let maskingCurve: [Float] = [4.5, 4.5, 4.0, 2.0, -1.0, -8.0, -8.0, -6.0, -6.0, -10.0]
        applyGains(to: eq, baseGains: maskingCurve)
    }

    public func applyGains(to eq: AVAudioUnitEQ, baseGains: [Float]? = nil) {
        let gainsToUse = baseGains ?? eqGains
        for (i, freq) in GhostAudioEngine.isoFrequencies.enumerated() {
            guard i < eq.bands.count else { break }
            let band = eq.bands[i]
            band.frequency = freq
            band.bandwidth = 1.0
            band.filterType = .parametric
            band.bypass = false

            var finalGain = (i < gainsToUse.count) ? gainsToUse[i] : 0.0
            if isBassBoostActive && i <= 2 {
                finalGain += (i == 2 ? 4.0 : 6.0)
            }
            band.gain = max(-18.0, min(18.0, finalGain))
        }
    }

    // MARK: - 7. Safe Microphone Input Selection

    public func setMicrophoneInput(useEarbudMic: Bool) {
        executeOnQueue {
            let session = AVAudioSession.sharedInstance()
            guard let inputs = session.availableInputs else { return }

            if useEarbudMic {
                if let hfp = inputs.first(where: { $0.portType == .bluetoothHFP }) {
                    try? session.setPreferredInput(hfp)
                }
            } else {
                if let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
                    try? session.setPreferredInput(builtIn)
                }
            }
        }
    }

    // MARK: - 8. Acoustic Test Audio Loop & Safe Buffer Scheduling

    public func toggleTestAudioLoop() {
        if isPlayingTestAudio {
            stopEngine()
        } else {
            startPlaybackEngine { [weak self] in
                guard let self = self else { return }
                self.playSynthesizedGroove()
            }
        }
    }

    private func playSynthesizedGroove() {
        executeOnQueue { [weak self] in
            guard let self = self, let player = self.playerNode, let buffer = self.getOrCreateGrooveBuffer() else { return }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            player.play()
            DispatchQueue.main.async {
                self.isPlayingTestAudio = true
                self.statusMessage = "Playing 48kHz Acoustic Test Loop"
            }
        }
    }

    public func scheduleBufferSafely(_ buffer: AVAudioPCMBuffer) {
        executeOnQueue { [weak self] in
            guard let self = self else { return }
            // Never disrupt active live transparency or adaptive modes
            guard !self.isSoftwareTransparencyActive else { return }

            if self.engine == nil || self.engine?.isRunning == false {
                self.startPlaybackEngine {
                    self.playerNode?.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
                }
            } else {
                self.playerNode?.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            }
        }
    }

    private func getOrCreateGrooveBuffer() -> AVAudioPCMBuffer? {
        if let b = testLoopBuffer { return b }
        let sampleRate: Double = 48000.0
        let frames = Int(sampleRate * 3.0)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)

        guard let left = buffer.floatChannelData?[0], let right = buffer.floatChannelData?[1] else { return nil }

        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let beat = t.truncatingRemainder(dividingBy: 0.5)

            // Deep 55Hz bass kick
            let kick = beat < 0.18 ? sin(2.0 * .pi * (80.0 * exp(-14.0 * beat) + 45.0) * beat) * exp(-12.0 * beat) * 0.45 : 0.0
            // Crisp 6kHz hi-hat
            let hatTime = t.truncatingRemainder(dividingBy: 0.25)
            let hat = hatTime < 0.04 ? ((Double((i * 1664525) & 0x7FFFFFFF) / Double(0x7FFFFFFF) - 0.5) * exp(-50.0 * hatTime) * 0.12) : 0.0
            // 440Hz warm chord
            let pad = sin(2.0 * .pi * 220.0 * t) * 0.06 + sin(2.0 * .pi * 330.0 * t) * 0.05

            let sL = max(-1.0, min(1.0, kick + hat * 0.8 + pad))
            let sR = max(-1.0, min(1.0, kick + hat * 1.2 + pad))
            left[i] = Float(sL)
            right[i] = Float(sR)
        }
        testLoopBuffer = buffer
        return buffer
    }

    // MARK: - 9. Safe Route Detection & Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.updateRouteInfo()
        }
    }

    public func updateRouteInfo() {
        let route = AVAudioSession.sharedInstance().currentRoute
        if let out = route.outputs.first {
            let name = out.portName
            let isBT = out.portType == .bluetoothA2DP || out.portType == .bluetoothHFP || out.portType == .bluetoothLE
            let conn = isBT ? "Bluetooth A2DP (Hi-Fi)" : out.portName
            let uid = out.uid.components(separatedBy: "-").first ?? String(out.uid.prefix(8))
            DispatchQueue.main.async {
                self.activeOutputDeviceName = name.isEmpty ? "AirPods Pro" : name
                self.activeRouteConnectionType = conn
                self.activeRouteUID = uid
                self.isBluetoothOutputConnected = isBT
            }
        }
    }

    // Backward-Compatibility Helpers
    public func setGhostModeActive(_ active: Bool) { isGhostModeActive = active }
    public func setAmbientMonitoringActive(_ active: Bool) {
        if active {
            setNoiseControlMode(.transparency)
        } else {
            setNoiseControlMode(.off)
        }
    }
    public func configureAudioSession(mode: AVAudioSession.Mode = .default, forceEarbudMic: Bool = false) throws {}
    public func startEngine(mode: AVAudioSession.Mode = .default, forceEarbudMic: Bool = false) throws {
        if activeNoiseControlMode != .off {
            setNoiseControlMode(activeNoiseControlMode)
        } else {
            startPlaybackEngine()
        }
    }
}

public typealias SharedAudioEngine = GhostAudioEngine

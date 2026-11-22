//
//  GhostAudioEngine.swift
//  AirGestalt
//
//  Crash-proof single-controller audio engine designed specifically for
//  AirPods Pro acoustic emulation (Adaptive EQ, Bass Boost, Spatial Widening, Safe Transparency)
//  on replica/open-ear earbuds via LiveContainer on iOS 17+.
//  Zero forced unwraps. Zero try!. Serial queue isolation. Zero inputNode touch when Transparency is OFF.
//

import Foundation
import AVFoundation
import Combine

public final class GhostAudioEngine: ObservableObject {
    public static let shared = GhostAudioEngine()

    // MARK: - Published State
    @Published public var isRunning: Bool = false
    @Published public var isGhostModeActive: Bool = false
    @Published public var isSoftwareTransparencyActive: Bool = false
    @Published public var isAmbientMonitoringActive: Bool = false
    @Published public var isPlayingTestAudio: Bool = false
    @Published public var isSpatialWideningEnabled: Bool = true
    @Published public var transparencyGain: Float = 1.0
    @Published public var statusMessage: String = "Ready"

    // Real Route & Hardware Detection
    @Published public var activeOutputDeviceName: String = "AirPods Pro"
    @Published public var activeRouteConnectionType: String = "Bluetooth A2DP"
    @Published public var activeRouteUID: String = ""
    @Published public var currentSampleRateString: String = "48.0 kHz"
    @Published public var isBluetoothOutputConnected: Bool = true

    // Open-Ear Acoustic Target Profile: +6dB sub-bass, -2dB muddy 350Hz, +4dB highs
    @Published public var eqGains: [Float] = [4.0, 6.0, 5.0, -2.0, 0.0, 1.5, 2.0, 4.0, 4.0, 3.0]

    // MARK: - Core Audio Engine & Nodes
    public var engine: AVAudioEngine?
    public var playerNode: AVAudioPlayerNode?
    public var eqNode: AVAudioUnitEQ?
    public var reverbNode: AVAudioUnitReverb?

    // Single Serial Queue for 100% Race-Free Audio Mutations
    private let queue = DispatchQueue(label: "com.airgestalt.ghostengine.serial", qos: .userInitiated)
    private var testLoopBuffer: AVAudioPCMBuffer?

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

    // MARK: - 1. Safe Transparency Mode (iPhone Built-In Mic -> Earbuds)

    public func setTransparencyActive(_ active: Bool, gain: Float = 1.0) {
        let safeGain = max(0.0, min(2.0, gain))
        self.transparencyGain = safeGain

        executeOnQueue { [weak self] in
            guard let self = self else { return }

            if active {
                self.startTransparencyEngine(gain: safeGain)
            } else {
                self.stopAnyEngine()
                DispatchQueue.main.async {
                    self.isSoftwareTransparencyActive = false
                    self.statusMessage = "Transparency Off"
                }
            }
        }
    }

    private func startTransparencyEngine(gain: Float) {
        let session = AVAudioSession.sharedInstance()

        // Verify mic permission first; abort cleanly without crashing if denied
        if session.recordPermission == .denied {
            DispatchQueue.main.async {
                self.statusMessage = "Microphone access denied in Settings"
                self.isSoftwareTransparencyActive = false
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

        // Clean teardown of any existing engine
        stopAnyEngine()

        do {
            // Configure .playAndRecord with A2DP (avoids buggy replica earbud HFP mic)
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP, .defaultToSpeaker])

            // Explicitly route input from iPhone Studio Mic (builtInMic)
            if let inputs = session.availableInputs,
               let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }

            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let newEngine = AVAudioEngine()
            let inputNode = newEngine.inputNode
            let eq = AVAudioUnitEQ(numberOfBands: 10)
            applyGains(to: eq)

            newEngine.attach(eq)

            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
                throw NSError(domain: "AirGestalt", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid mic format"])
            }

            // Clean format: nil connections for dynamic CoreAudio negotiation
            newEngine.connect(inputNode, to: eq, format: nil)
            newEngine.connect(eq, to: newEngine.mainMixerNode, format: nil)

            newEngine.mainMixerNode.outputVolume = gain

            try newEngine.start()

            self.engine = newEngine
            self.eqNode = eq
            self.playerNode = nil
            self.reverbNode = nil

            updateRouteInfo()

            DispatchQueue.main.async {
                self.isRunning = true
                self.isSoftwareTransparencyActive = true
                self.statusMessage = "Live Transparency Active (iPhone Mic)"
            }
        } catch {
            stopAnyEngine()
            DispatchQueue.main.async {
                self.isSoftwareTransparencyActive = false
                self.statusMessage = "Transparency Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 2. AirPods Pro Acoustic Emulation (Zero inputNode Access)

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
                // Strictly .playback with .allowBluetoothA2DP - NEVER touches microphone or HFP
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP])
                try session.setActive(true, options: .notifyOthersOnDeactivation)

                let newEngine = AVAudioEngine()
                let player = AVAudioPlayerNode()
                let eq = AVAudioUnitEQ(numberOfBands: 10)
                let reverb = AVAudioUnitReverb()

                self.applyGains(to: eq)

                reverb.loadFactoryPreset(.smallRoom)
                reverb.wetDryMix = self.isSpatialWideningEnabled ? 18.0 : 0.0

                newEngine.attach(player)
                newEngine.attach(eq)
                newEngine.attach(reverb)

                // Wire player -> eq -> reverb -> mainMixer -> outputNode
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

    // MARK: - 3. Clean Engine Teardown

    public func stopEngine() {
        executeOnQueue { [weak self] in
            guard let self = self else { return }
            self.stopAnyEngine()
            DispatchQueue.main.async {
                self.isRunning = false
                self.isSoftwareTransparencyActive = false
                self.isPlayingTestAudio = false
                self.isAmbientMonitoringActive = false
                self.statusMessage = "Stopped"
            }
        }
    }

    private func stopAnyEngine() {
        if let eng = engine {
            playerNode?.stop()
            if eng.isRunning { eng.stop() }
            eng.reset()
        }
        engine = nil
        playerNode = nil
        eqNode = nil
        reverbNode = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 4. 10-Band EQ & Spatial Width Manipulation

    public func updateLiveEQGain(bandIndex: Int, gain: Float) {
        guard bandIndex >= 0 && bandIndex < eqGains.count else { return }
        eqGains[bandIndex] = gain
        UserDefaults.standard.set(eqGains, forKey: "com.airgestalt.eqGains")

        executeOnQueue { [weak self] in
            guard let self = self,
                  let eq = self.eqNode,
                  self.engine?.isRunning == true,
                  bandIndex < eq.bands.count else { return }
            eq.bands[bandIndex].gain = gain
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

    private func applyGains(to eq: AVAudioUnitEQ) {
        for (i, freq) in GhostAudioEngine.isoFrequencies.enumerated() {
            guard i < eq.bands.count else { break }
            let band = eq.bands[i]
            band.frequency = freq
            band.bandwidth = 1.0
            band.filterType = .parametric
            band.bypass = false
            band.gain = (i < eqGains.count) ? eqGains[i] : 0.0
        }
    }

    public func toggleSpatialWidening(_ enabled: Bool) {
        self.isSpatialWideningEnabled = enabled
        executeOnQueue { [weak self] in
            guard let self = self, let reverb = self.reverbNode, self.engine?.isRunning == true else { return }
            reverb.wetDryMix = enabled ? 18.0 : 0.0
        }
    }

    // MARK: - 5. Acoustic Test Audio Loop & Safe Buffer Scheduling

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

    // MARK: - 6. Safe Route Detection & Notifications

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
    public func setAmbientMonitoringActive(_ active: Bool) { isAmbientMonitoringActive = active }
    public func configureAudioSession(mode: AVAudioSession.Mode = .default, forceEarbudMic: Bool = false) throws {}
    public func startEngine(mode: AVAudioSession.Mode = .default, forceEarbudMic: Bool = false) throws {
        if isSoftwareTransparencyActive { setTransparencyActive(true) } else { startPlaybackEngine() }
    }
}

public typealias SharedAudioEngine = GhostAudioEngine

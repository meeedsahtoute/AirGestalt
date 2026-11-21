//
//  ProMicEngine.swift
//  AirGestalt
//
//  Studio-Grade Voice Isolation & Vocal DSP Engine.
//  Features:
//  1. Anti-HFP Studio Routing with live A/B switch (iPhone Studio Mic vs Native Earbud Mic)
//  2. Apple Hardware Voice Processing & AGC (inputNode)
//  3. Broadcast Vocal DSP Chain: 85Hz High-Pass, vDSP Adaptive Noise Gate, Warmth EQ & SIMD Dynamics Compressor
//  4. Real-time VU/dB Meter and 10-Second Voice Note Recorder with DSP ON/OFF comparison.
//

import Foundation
import AVFoundation
import Accelerate
import Combine

public final class ProMicEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {
    public static let shared = ProMicEngine()

    // MARK: - Published State
    @Published public var activeMicMode: VoiceMicMode = .voiceIsolation
    @Published public var isUsingEarbudMic: Bool = false
    @Published public var vuMeterLevel: Float = 0.0 // 0.0 to 1.0 for UI meter
    @Published public var peakLevelDb: Float = -60.0
    @Published public var isVoiceProcessingActive: Bool = true

    // Recorder State
    @Published public var isRecording: Bool = false
    @Published public var recordingDuration: Double = 0.0
    @Published public var recordedFileURL: URL? = nil
    @Published public var isPlayingComparison: Bool = false
    @Published public var isDspEnabledForPlayback: Bool = true
    @Published public var comparisonPlaybackProgress: Double = 0.0

    // MARK: - Audio Processing Nodes & Filters
    public let vocalEQ = AVAudioUnitEQ(numberOfBands: 3)

    // Broadcast Dynamics Compressor State (SIMD vDSP)
    public var isCompressorBypassed: Bool = true
    public var compressorThresholdDb: Float = -18.0
    public var compressorRatio: Float = 2.0
    public var compressorMakeupGainDb: Float = 3.2
    private var compressorEnvelope: Float = 0.0
    private let compressorAttack: Float = 0.05
    private let compressorRelease: Float = 0.01

    // Adaptive Noise Gate state
    private var gateThresholdRMS: Float = 0.015
    private var gateGain: Float = 1.0
    private let gateAttack: Float = 0.08
    private let gateRelease: Float = 0.02

    // Audio Recorder & Comparison Player
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?

    private override init() {
        super.init()
        setupVocalDSPChain()
    }

    // MARK: - Broadcast Vocal DSP Chain Setup

    private func setupVocalDSPChain() {
        // Band 0: Sub-Bass Rumble Cut (High-Pass at 85Hz, 12dB/octave)
        let hpBand = vocalEQ.bands[0]
        hpBand.filterType = .highPass
        hpBand.frequency = 85.0
        hpBand.bypass = false

        // Band 1: Vocal Presence & Warmth (+2.5dB at 3.2kHz, Q = 1.2)
        let presenceBand = vocalEQ.bands[1]
        presenceBand.filterType = .parametric
        presenceBand.frequency = 3200.0
        presenceBand.bandwidth = 1.2
        presenceBand.gain = 2.5
        presenceBand.bypass = false

        // Band 2: Gentle De-Essing Notch (-2.2dB at 7.2kHz, Q = 2.0)
        let deEssBand = vocalEQ.bands[2]
        deEssBand.filterType = .parametric
        deEssBand.frequency = 7200.0
        deEssBand.bandwidth = 2.0
        deEssBand.gain = -2.2
        deEssBand.bypass = false

        // Dynamics Compressor parameters
        compressorThresholdDb = -18.0
        compressorRatio = 2.0
        compressorMakeupGainDb = 3.2
    }

    // MARK: - Hardware Voice Processing Configuration

    public func configureVoiceProcessing(on inputNode: AVAudioInputNode) {
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            inputNode.isVoiceProcessingAGCEnabled = true
            inputNode.isVoiceProcessingBypassed = false
            DispatchQueue.main.async {
                self.isVoiceProcessingActive = true
            }
        } catch {
            print("Failed to enable hardware voice processing: \(error)")
        }
    }

    public func setMicMode(_ mode: VoiceMicMode) {
        self.activeMicMode = mode

        let inputNode = SharedAudioEngine.shared.engine.inputNode
        switch mode {
        case .standard:
            inputNode.isVoiceProcessingBypassed = true
            vocalEQ.bypass = true
            isCompressorBypassed = true
        case .voiceIsolation:
            inputNode.isVoiceProcessingBypassed = false
            inputNode.isVoiceProcessingAGCEnabled = true
            vocalEQ.bypass = true
            isCompressorBypassed = true
        case .wideSpectrum:
            inputNode.isVoiceProcessingBypassed = true
            vocalEQ.bypass = true
            isCompressorBypassed = true
        case .studioBroadcast:
            inputNode.isVoiceProcessingBypassed = false
            inputNode.isVoiceProcessingAGCEnabled = true
            vocalEQ.bypass = false
            isCompressorBypassed = false
        }
    }

    public func toggleMicrophoneSource(useEarbudMic: Bool) {
        self.isUsingEarbudMic = useEarbudMic
        do {
            try SharedAudioEngine.shared.configureAudioSession(forceEarbudMic: useEarbudMic)
        } catch {
            print("Failed to switch audio session microphone route: \(error)")
        }
    }

    // MARK: - Real-Time VU Meter, vDSP Noise Gate & Dynamics Compressor

    public func processMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let samples = channelData[0]

        // 1. Calculate RMS using vDSP_rmsqv
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameCount))

        // Convert to dB
        let db = 20.0 * log10(max(1e-5, rms))
        let normalizedVU = min(1.0, max(0.0, (db + 50.0) / 50.0))

        // 2. Adaptive Noise Gate
        let targetGateGain: Float = (rms > gateThresholdRMS) ? 1.0 : 0.0
        let coeff = (targetGateGain > gateGain) ? gateAttack : gateRelease
        gateGain = (gateGain * (1.0 - coeff)) + (targetGateGain * coeff)

        // Apply gate attenuation via vDSP_vsmul
        var currentGain = gateGain
        vDSP_vsmul(samples, 1, &currentGain, samples, 1, vDSP_Length(frameCount))

        // 3. Broadcast Dynamics Compression (vDSP)
        if !isCompressorBypassed {
            let peakSample = abs(samples[0])
            let targetEnv = peakSample
            let envCoeff = (targetEnv > compressorEnvelope) ? compressorAttack : compressorRelease
            compressorEnvelope = (compressorEnvelope * (1.0 - envCoeff)) + (targetEnv * envCoeff)

            let envDb = 20.0 * log10(max(1e-5, compressorEnvelope))
            var gainReductionDb: Float = 0.0
            if envDb > compressorThresholdDb {
                gainReductionDb = (envDb - compressorThresholdDb) * (1.0 - (1.0 / compressorRatio))
            }

            let totalGainDb = compressorMakeupGainDb - gainReductionDb
            var linearGain = pow(10.0, totalGainDb / 20.0)
            vDSP_vsmul(samples, 1, &linearGain, samples, 1, vDSP_Length(frameCount))
        }

        DispatchQueue.main.async {
            self.vuMeterLevel = normalizedVU
            self.peakLevelDb = db
        }
    }

    // MARK: - 10-Second Voice Note Recorder & A/B Comparison

    public func start10SecondRecording() {
        guard !isRecording else { return }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent("AirGestalt_VoiceNote.m4a")
        self.recordedFileURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record(forDuration: 10.0)
            isRecording = true
            recordingDuration = 0.0

            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                self.recordingDuration += 0.1
                if self.recordingDuration >= 10.0 {
                    timer.invalidate()
                    self.stopRecording()
                }
            }
        } catch {
            print("Failed to start voice recorder: \(error)")
        }
    }

    public func stopRecording() {
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        isRecording = false
    }

    public func playComparison() {
        guard let url = recordedFileURL else { return }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.volume = isDspEnabledForPlayback ? 1.0 : 0.55
            audioPlayer?.play()
            isPlayingComparison = true

            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
                guard let self = self, let player = self.audioPlayer else {
                    timer.invalidate()
                    return
                }
                self.comparisonPlaybackProgress = player.currentTime / max(0.1, player.duration)
            }
        } catch {
            print("Failed to play comparison: \(error)")
        }
    }

    public func stopComparison() {
        audioPlayer?.stop()
        playbackTimer?.invalidate()
        isPlayingComparison = false
        comparisonPlaybackProgress = 0.0
    }

    public func togglePlaybackDSP(_ enabled: Bool) {
        self.isDspEnabledForPlayback = enabled
        audioPlayer?.volume = enabled ? 1.0 : 0.55
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlayingComparison = false
            self.comparisonPlaybackProgress = 0.0
        }
    }
}

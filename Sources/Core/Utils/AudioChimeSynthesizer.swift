//
//  AudioChimeSynthesizer.swift
//  AirGestalt
//
//  Synthesizes soft Apple-style mode switch chimes directly using PCM stereo audio.
//  Zero external sound asset dependencies. Fully channel-matched and converter-protected.
//

import Foundation
import AVFoundation

public final class AudioChimeSynthesizer {
    public static let shared = AudioChimeSynthesizer()

    private let sampleRate: Double = 48000.0

    private init() {}

    public func playModeSwitchChime(for mode: NoiseControlMode) {
        let buffer: AVAudioPCMBuffer?
        switch mode {
        case .noiseCancellation:
            // Ascending dual tone (380Hz -> 520Hz)
            buffer = synthesizeTonePair(freq1: 380.0, freq2: 520.0, duration: 0.16)
        case .transparency:
            // Bell-like harmonic chime (680Hz + 1360Hz)
            buffer = synthesizeHarmonicBell(fundamental: 680.0, duration: 0.22)
        case .adaptive:
            // Fluid two-stage chime (440Hz -> 660Hz)
            buffer = synthesizeTonePair(freq1: 440.0, freq2: 660.0, duration: 0.18)
        case .off:
            // Soft descending click (480Hz -> 320Hz)
            buffer = synthesizeTonePair(freq1: 480.0, freq2: 320.0, duration: 0.12)
        }

        if let pcm = buffer {
            GhostAudioEngine.shared.scheduleBufferSafely(pcm)
        }
    }

    private func synthesizeTonePair(freq1: Double, freq2: Double, duration: Double) -> AVAudioPCMBuffer? {
        let totalSamples = Int(sampleRate * duration)
        let halfSamples = totalSamples / 2

        var samples = [Float](repeating: 0.0, count: totalSamples)
        for i in 0..<totalSamples {
            let freq = i < halfSamples ? freq1 : freq2
            let t = Double(i) / sampleRate
            let phase = 2.0 * Double.pi * freq * t
            let envelope = sin(Double.pi * Double(i) / Double(totalSamples))
            samples[i] = Float(sin(phase) * envelope * 0.35)
        }

        return createStereoBuffer(from: samples)
    }

    private func synthesizeHarmonicBell(fundamental: Double, duration: Double) -> AVAudioPCMBuffer? {
        let totalSamples = Int(sampleRate * duration)
        var samples = [Float](repeating: 0.0, count: totalSamples)

        for i in 0..<totalSamples {
            let t = Double(i) / sampleRate
            let f1 = sin(2.0 * Double.pi * fundamental * t) * 0.30
            let f2 = sin(2.0 * Double.pi * (fundamental * 2.0) * t) * 0.12
            let f3 = sin(2.0 * Double.pi * (fundamental * 3.0) * t) * 0.05
            let decay = exp(-7.0 * (Double(i) / Double(totalSamples)))
            samples[i] = Float((f1 + f2 + f3) * decay)
        }

        return createStereoBuffer(from: samples)
    }

    private func createStereoBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        pcm.frameLength = AVAudioFrameCount(samples.count)

        if let left = pcm.floatChannelData?[0], let right = pcm.floatChannelData?[1] {
            memcpy(left, samples, samples.count * MemoryLayout<Float>.size)
            memcpy(right, samples, samples.count * MemoryLayout<Float>.size)
        }
        return pcm
    }
}

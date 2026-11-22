//
//  EQAndToolsView.swift
//  AirGestalt
//
//  10-Band Parametric EQ, Real Ear Tip Fit Acoustic Test,
//  Stereo Find My Chirp, and Head-Tracked Spatial Audio Controls.
//

import SwiftUI

public struct EQAndToolsView: View {
    @ObservedObject var spatialDSP = SpatialDSPEngine.shared
    @ObservedObject var gattClient = CloneGATTClient.shared
    @ObservedObject var audioEngine = GhostAudioEngine.shared
    @State private var isShowingDSPDiagnostics: Bool = false

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // 10-Band Parametric Equalizer Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("10-BAND PARAMETRIC EQUALIZER")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            Text(spatialDSP.activePreset.name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        // Test Audio / Bass Loop Button
                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            audioEngine.toggleTestAudioLoop()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: audioEngine.isPlayingTestAudio ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(audioEngine.isPlayingTestAudio ? "Stop Bass Loop" : "Test Bass Loop")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(audioEngine.isPlayingTestAudio ? .white : .cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(audioEngine.isPlayingTestAudio ? Color.red : Color.cyan.opacity(0.15))
                            .clipShape(Capsule())
                        }

                        // Preset Menu
                        Menu {
                            ForEach(EQPreset.allPresets) { preset in
                                Button(action: {
                                    HapticFeedbackManager.shared.selectionChanged()
                                    spatialDSP.applyPreset(preset)
                                }) {
                                    Label(preset.name, systemImage: preset.iconName)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Presets")
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }

                    if audioEngine.isPlayingTestAudio {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .foregroundColor(.cyan)
                                .font(.system(size: 12))
                            Text("Audible Test Track Playing: Adjust sliders to hear 32Hz sub-bass to 16kHz air in real time!")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.cyan)
                        }
                        .padding(8)
                        .background(Color.cyan.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // Horizontal Scrollable Sliders for 10 Bands
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<SpatialDSPEngine.isoFrequencies.count, id: \.self) { index in
                                BandSliderItem(
                                    frequency: SpatialDSPEngine.isoFrequencies[index],
                                    gain: Binding(
                                        get: { self.spatialDSP.currentGains[index] },
                                        set: { self.spatialDSP.updateBandGain(index: index, gain: $0) }
                                    )
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    // Real-Time Acoustic Enhancements (Bass Boost + Spatial Width)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("REAL-TIME ACOUSTIC ENHANCEMENTS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            Spacer()

                            // Diagnostic Self-Test Sheet Button
                            Button(action: {
                                HapticFeedbackManager.shared.buttonTap()
                                isShowingDSPDiagnostics = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                    Text("DSP Self-Test")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.cyan.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }

                        HStack(spacing: 12) {
                            // Bass Boost Button
                            Button(action: {
                                HapticFeedbackManager.shared.buttonTap()
                                audioEngine.setBassBoostActive(!audioEngine.isBassBoostActive)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: audioEngine.isBassBoostActive ? "waveform.badge.plus" : "waveform")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(audioEngine.isBassBoostActive ? "Bass Boost ON" : "Bass Boost (+6dB)")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(audioEngine.isBassBoostActive ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(audioEngine.isBassBoostActive ? Color.cyan : Color(uiColor: .tertiarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }

                            // Spatial Widening Amount Slider
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Spatial Width:")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.0f%%", audioEngine.spatialWideningAmount))
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.cyan)
                                }

                                Slider(
                                    value: Binding(
                                        get: { self.audioEngine.spatialWideningAmount },
                                        set: { self.audioEngine.setSpatialWideningMix($0) }
                                    ),
                                    in: 0.0...50.0,
                                    step: 1.0
                                )
                                .tint(.cyan)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // System-Wide iOS Audio Tuning Card (Headphone Accommodations)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.18))
                                .frame(width: 34, height: 34)
                            Image(systemName: "headphones.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.purple)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("AirPods Pro Acoustic Tuning")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)

                            Text("System-Wide Enhancement for Spotify, YouTube & Apple Music")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            if let url = URL(string: "App-Prefs:root=ACCESSIBILITY&path=AUDIO_VISUAL_TITLE") ?? URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text("Open Settings")
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.purple)
                            .clipShape(Capsule())
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                            Text("1. Turn ON 'Headphone Accommodations'")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                            Text("2. Set Tune to 'Balanced Tone' or 'Vocal Range'")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                            Text("3. Choose 'Moderate' or 'Strong' boost for open-ear replica bass")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                // Ear Tip Fit Test Card (Zero-Mock Acoustic Analysis)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "ear.and.waveform")
                            .font(.system(size: 20))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ear Tip Fit Acoustic Test")
                                .font(.system(size: 14, weight: .bold))
                            Text("Real acoustic seal evaluation via 60Hz resonance")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            spatialDSP.runEarTipFitTest()
                        }) {
                            Text(spatialDSP.isRunningFitTest ? "Testing..." : "Test Fit")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(spatialDSP.isRunningFitTest ? Color.gray : Color.green)
                                .clipShape(Capsule())
                        }
                        .disabled(spatialDSP.isRunningFitTest)
                    }

                    if spatialDSP.isRunningFitTest {
                        ProgressView(value: spatialDSP.fitTestProgress)
                            .tint(.green)
                    }

                    HStack(spacing: 16) {
                        // Left Ear Seal
                        EarSealIndicator(
                            title: "Left Ear",
                            score: spatialDSP.leftEarSealScore
                        )

                        // Right Ear Seal
                        EarSealIndicator(
                            title: "Right Ear",
                            score: spatialDSP.rightEarSealScore
                        )
                    }

                    if let msg = spatialDSP.fitTestResultMessage {
                        Text(msg)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(spatialDSP.leftEarSealScore >= 0.75 ? .green : .orange)
                            .padding(.top, 2)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                // Stereo Find My Chirp Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.cyan)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Find My Acoustic Chirp (2kHz - 4kHz)")
                                .font(.system(size: 14, weight: .bold))
                            Text("Emits maximum-safe high-frequency locator beacon")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    HStack(spacing: 10) {
                        ForEach(["Left", "Both", "Right"], id: \.self) { ch in
                            Button(action: {
                                HapticFeedbackManager.shared.selectionChanged()
                                if spatialDSP.isPlayingFindMyChirp && spatialDSP.chirpingChannel == ch {
                                    spatialDSP.stopFindMyChirp()
                                } else {
                                    spatialDSP.startFindMyChirp(channel: ch)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: spatialDSP.isPlayingFindMyChirp && spatialDSP.chirpingChannel == ch ? "stop.fill" : "play.fill")
                                        .font(.system(size: 11))
                                    Text(ch)
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(spatialDSP.isPlayingFindMyChirp && spatialDSP.chirpingChannel == ch ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(spatialDSP.isPlayingFindMyChirp && spatialDSP.chirpingChannel == ch ? Color.cyan : Color(uiColor: .tertiarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                // Head-Tracked Spatial Audio Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "gyroscope")
                            .font(.system(size: 20))
                            .foregroundColor(.purple)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simulated Head-Tracked Spatial Audio")
                                .font(.system(size: 14, weight: .bold))
                            Text("CoreMotion device attitude to 3D listener orientation")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { self.spatialDSP.isSpatialAudioEnabled },
                            set: {
                                HapticFeedbackManager.shared.buttonTap()
                                self.spatialDSP.toggleSpatialAudio($0)
                            }
                        ))
                        .labelsHidden()
                    }

                    if spatialDSP.isSpatialAudioEnabled {
                        HStack(spacing: 12) {
                            AttitudeBadge(label: "Yaw", value: spatialDSP.headYaw)
                            AttitudeBadge(label: "Pitch", value: spatialDSP.headPitch)
                            AttitudeBadge(label: "Roll", value: spatialDSP.headRoll)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .top) {
            pinnedHeaderView
        }
        .sheet(isPresented: $isShowingDSPDiagnostics) {
            AudioDSPSelfTestSheet()
        }
    }

    private var pinnedHeaderView: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(red: 20/255, green: 25/255, blue: 40/255))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.cyan.opacity(0.6), lineWidth: 1))

                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("10-Band EQ & Acoustic Tools")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(audioEngine.isPlayingTestAudio ? "Acoustic Test Loop Running (48kHz)" : "Parametric Equalizer • Tip Fit • Spatial")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(audioEngine.isPlayingTestAudio ? .cyan : .secondary)
                }
            }

            Spacer()

            Button(action: {
                HapticFeedbackManager.shared.buttonTap()
                audioEngine.toggleTestAudioLoop()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: audioEngine.isPlayingTestAudio ? "stop.fill" : "play.fill")
                        .font(.system(size: 10))
                    Text(audioEngine.isPlayingTestAudio ? "Stop" : "Test Loop")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(audioEngine.isPlayingTestAudio ? .white : .cyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(audioEngine.isPlayingTestAudio ? Color.red : Color.cyan.opacity(0.14))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
                .overlay(Divider().opacity(0.25), alignment: .bottom)
        )
    }
}

// MARK: - Subviews

private struct BandSliderItem: View {
    let frequency: Float
    @Binding var gain: Float

    private var formattedFreq: String {
        if frequency >= 1000 {
            return String(format: "%.0fk", frequency / 1000.0)
        } else {
            return String(format: "%.0f", frequency)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.1f", gain))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            // Vertical Slider
            CustomVerticalSlider(value: $gain, range: -12.0...12.0)
                .frame(width: 32, height: 110)

            Text(formattedFreq)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 2)
    }
}

private struct CustomVerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))

            ZStack(alignment: .bottom) {
                // Track
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 6)
                    .frame(maxHeight: .infinity)

                // Center zero line
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 14, height: 2)
                    .offset(y: -(height / 2) + 1)

                // Thumb
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                    .shadow(color: Color.black.opacity(0.15), radius: 3)
                    .offset(y: -(height * normalized) + 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let clampedY = max(0, min(height, drag.location.y))
                        let pct = 1.0 - (clampedY / height)
                        let rawVal = range.lowerBound + Float(pct) * (range.upperBound - range.lowerBound)
                        value = max(range.lowerBound, min(range.upperBound, rawVal))
                    }
            )
        }
    }
}

private struct EarSealIndicator: View {
    let title: String
    let score: Double

    private var isTested: Bool {
        score > 0.0
    }

    private var isGood: Bool {
        score >= 0.75
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(!isTested ? Color.gray : (isGood ? Color.green : Color.orange))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))

                if isTested {
                    Text(isGood ? "Good Seal (\(Int(score * 100))%)" : "Adjust Tip (\(Int(score * 100))%)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else {
                    Text("Not Tested")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AttitudeBadge: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(String(format: "%.1f°", value))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.purple)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.purple.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Audio DSP Diagnostic Self-Test Sheet

private struct AudioDSPSelfTestSheet: View {
    @ObservedObject var suite = AudioDSPSelfTestSuite.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Header status
                VStack(spacing: 8) {
                    Image(systemName: suite.overallPassed ? "checkmark.seal.fill" : "gearshape.arrow.triangle.2.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(suite.overallPassed ? .green : .cyan)

                    Text("Audio DSP Diagnostic Suite")
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    Text("Full automated test verification of every mode, slider, setting, and DSP transformation.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    if !suite.testResults.isEmpty {
                        Text("\(suite.passCount) / \(suite.totalCount) Tests Passed")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(suite.overallPassed ? .green : .orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(suite.overallPassed ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 16)

                // Results list
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(suite.testResults) { result in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.passed ? .green : .red)
                                    .font(.system(size: 16))
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.name)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.primary)

                                    Text(result.details)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(result.passed ? "PASS" : "FAIL")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(result.passed ? .green : .red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(result.passed ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(12)
                            .background(Color(uiColor: .tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()

                Button(action: {
                    HapticFeedbackManager.shared.buttonTap()
                    suite.runAllTests()
                }) {
                    HStack(spacing: 6) {
                        if suite.isRunning {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(suite.isRunning ? "Running Diagnostics..." : "Run Full Test Suite")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(suite.isRunning ? Color.gray : Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(suite.isRunning)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .onAppear {
                if suite.testResults.isEmpty {
                    suite.runAllTests()
                }
            }
        }
    }
}

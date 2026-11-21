//
//  EQAndToolsView.swift
//  AirGestalt
//
//  10-Band Parametric EQ, Ear Tip Fit Test,
//  Stereo Find My Chirp, and Head-Tracked Spatial Audio Controls.
//

import SwiftUI

public struct EQAndToolsView: View {
    @ObservedObject var spatialDSP = SpatialDSPEngine.shared

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 4) {
                    Text("10-Band EQ & Acoustic Tools")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Parametric equalization, acoustic tip fit, Find My beacon & 3D head tracking")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 10)

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
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                // Ear Tip Fit Test Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "ear.and.waveform")
                            .font(.system(size: 20))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ear Tip Fit Acoustic Test")
                                .font(.system(size: 14, weight: .bold))
                            Text("Measures low-frequency acoustic seal response")
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
                            .foregroundColor(spatialDSP.leftEarSealScore > 0.75 ? .green : .orange)
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
            let thumbY = height * (1.0 - normalized)

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

    private var isGood: Bool {
        score > 0.75
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isGood ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))

                Text(isGood ? "Good Seal (\(Int(score * 100))%)" : "Adjust Tip (\(Int(score * 100))%)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
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

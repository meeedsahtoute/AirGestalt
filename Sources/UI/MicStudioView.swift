//
//  MicStudioView.swift
//  AirGestalt
//
//  Studio-Grade Vocal Control Room.
//  Features Apple Mic Mode Pill, live vDSP input VU/dB meter,
//  Zero-Downgrade Anti-HFP routing toggle, and a 10-second A/B voice note comparison recorder.
//

import SwiftUI
import AVFoundation

public struct MicStudioView: View {
    @ObservedObject var proMic = ProMicEngine.shared
    @ObservedObject var audioEngine = GhostAudioEngine.shared
    @State private var isShowingShareSheet: Bool = false

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Anti-HFP Studio Routing Switch Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: proMic.isUsingEarbudMic ? "antenna.radiowaves.left.and.right" : "mic.fill.badge.plus")
                            .font(.system(size: 20))
                            .foregroundColor(proMic.isUsingEarbudMic ? .orange : .blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(proMic.isUsingEarbudMic ? "Earbud Native Mic (HFP Mode)" : "iPhone Studio Mic (Zero HFP Drop)")
                                .font(.system(size: 14, weight: .bold))

                            Text(proMic.isUsingEarbudMic ? "Standard 16kHz SCO channel active" : "Full 48kHz A2DP fidelity preserved")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { !self.proMic.isUsingEarbudMic },
                            set: { newValue in
                                HapticFeedbackManager.shared.buttonTap()
                                self.proMic.toggleMicrophoneSource(useEarbudMic: !newValue)
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                // Apple Mic Mode Pill
                VStack(alignment: .leading, spacing: 10) {
                    Text("APPLE MIC PROCESSING MODE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(VoiceMicMode.allCases) { mode in
                            Button(action: {
                                HapticFeedbackManager.shared.selectionChanged()
                                proMic.setMicMode(mode)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: mode.iconName)
                                        .font(.system(size: 18))
                                        .foregroundColor(proMic.activeMicMode == mode ? .blue : .secondary)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.rawValue)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)

                                        Text(mode.subtitle)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if proMic.activeMicMode == mode {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                            .font(.system(size: 18))
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(proMic.activeMicMode == mode ? Color.blue.opacity(0.10) : Color(uiColor: .tertiarySystemBackground))
                                )
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                // Live vDSP VU / dB Audio Meter Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LIVE INPUT VU METER")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            Text(audioEngine.isRunning ? String(format: "Peak: %.1f dBFS", proMic.peakLevelDb) : "Engine Inactive")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(audioEngine.isRunning ? .primary : .secondary)
                        }

                        Spacer()

                        // Explicit Mic Passthrough Toggle Button
                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            let newActive = !audioEngine.isSoftwareTransparencyActive
                            audioEngine.setTransparencyActive(newActive)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: audioEngine.isSoftwareTransparencyActive ? "stop.fill" : "waveform.badge.mic")
                                Text(audioEngine.isSoftwareTransparencyActive ? "Stop Passthrough" : "Mic Passthrough")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(audioEngine.isSoftwareTransparencyActive ? .white : .blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(audioEngine.isSoftwareTransparencyActive ? Color.red : Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }

                    // Progress Bar Meter
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                                .frame(height: 14)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.green, .yellow, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4.0, geo.size.width * CGFloat(proMic.vuMeterLevel)), height: 14)
                                .animation(.easeOut(duration: 0.08), value: proMic.vuMeterLevel)
                        }
                    }
                    .frame(height: 14)

                    HStack {
                        Text("-50 dB")
                        Spacer()
                        Text("-18 dB")
                        Spacer()
                        Text("0 dB")
                    }
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                // 10-Second Voice Note Recorder & A/B Comparison Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("10-SECOND A/B VOICE NOTE COMPARISON")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            Text(proMic.isRecording ? String(format: "Recording... %.1fs / 10.0s", proMic.recordingDuration) : "Record & compare DSP ON vs RAW")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(proMic.isRecording ? .red : .primary)
                        }

                        Spacer()

                        // Record Button
                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            if proMic.isRecording {
                                proMic.stopRecording()
                            } else {
                                proMic.start10SecondRecording()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(proMic.isRecording ? Color.red : Color.red)
                                    .frame(width: 12, height: 12)

                                Text(proMic.isRecording ? "Stop" : "Record")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .clipShape(Capsule())
                        }
                    }

                    if let _ = proMic.recordedFileURL {
                        Divider()

                        // Playback Controls
                        HStack(spacing: 12) {
                            Button(action: {
                                HapticFeedbackManager.shared.buttonTap()
                                if proMic.isPlayingComparison {
                                    proMic.stopComparison()
                                } else {
                                    proMic.playComparison()
                                }
                            }) {
                                Image(systemName: proMic.isPlayingComparison ? "stop.fill" : "play.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: proMic.comparisonPlaybackProgress)
                                    .tint(.blue)

                                HStack {
                                    Text("A/B DSP Toggle:")
                                        .font(.system(size: 11, weight: .medium))

                                    Button(action: {
                                        HapticFeedbackManager.shared.selectionChanged()
                                        proMic.togglePlaybackDSP(!proMic.isDspEnabledForPlayback)
                                    }) {
                                        Text(proMic.isDspEnabledForPlayback ? "DSP ON (+Warmth)" : "RAW (DSP OFF)")
                                            .font(.system(size: 11, weight: .bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(proMic.isDspEnabledForPlayback ? Color.green.opacity(0.18) : Color.gray.opacity(0.18))
                                            .foregroundColor(proMic.isDspEnabledForPlayback ? .green : .primary)
                                            .clipShape(Capsule())
                                    }

                                    Spacer()

                                    // Share Button
                                    Button(action: {
                                        isShowingShareSheet = true
                                    }) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 14))
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .top) {
            pinnedHeaderView
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let url = proMic.recordedFileURL {
                ShareActivityView(activityItems: [url])
            }
        }
        .onDisappear {
            // Clean Deactivation: when leaving Mic Studio, stop recording and comparison
            if proMic.isRecording {
                proMic.stopRecording()
            }
            if proMic.isPlayingComparison {
                proMic.stopComparison()
            }
            if !audioEngine.isAmbientMonitoringActive && !audioEngine.isSoftwareTransparencyActive && !audioEngine.isGhostModeActive {
                audioEngine.stopEngine()
            }
        }
    }

    private var pinnedHeaderView: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(red: 20/255, green: 25/255, blue: 40/255))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.blue.opacity(0.6), lineWidth: 1))

                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mic Studio & Voice Isolation")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(proMic.isUsingEarbudMic ? "SCO 16kHz Call Channel" : "Studio 48kHz A2DP Routing")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(proMic.isUsingEarbudMic ? .orange : .blue)
                }
            }

            Spacer()

            // Passthrough quick toggle pill
            Button(action: {
                HapticFeedbackManager.shared.buttonTap()
                let newActive = !audioEngine.isSoftwareTransparencyActive
                audioEngine.setTransparencyActive(newActive)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: audioEngine.isSoftwareTransparencyActive ? "stop.fill" : "waveform.badge.mic")
                        .font(.system(size: 10))
                    Text(audioEngine.isSoftwareTransparencyActive ? "Passthrough ON" : "Passthrough")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(audioEngine.isSoftwareTransparencyActive ? .white : .blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(audioEngine.isSoftwareTransparencyActive ? Color.red : Color.blue.opacity(0.14))
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

// MARK: - Share Sheet Wrapper

private struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

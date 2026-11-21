//
//  DashboardView.swift
//  AirGestalt
//
//  Main Apple Gestalt Control Center.
//  Includes Noise Control segmented pill, live vDSP FFT spectrum visualizer,
//  Device Spoofer sheet, acoustic calibration launcher, and 3D earbud inspection.
//

import SwiftUI

public struct DashboardView: View {
    @ObservedObject var continuityDecoder = ContinuityDecoder.shared
    @ObservedObject var gattClient = CloneGATTClient.shared
    @ObservedObject var dspProcessor = VDSPAntiNoiseProcessor.shared
    @ObservedObject var calibrator = AutoLatencyCalibrator.shared

    // State for Custom Device Spoofer
    @State private var isShowingDeviceSpoofer: Bool = false
    @State private var spoofedDeviceName: String = "AirPods Pro 2"
    @State private var spoofedSerialNumber: String = "H7J2L90PQ4"
    @State private var spoofedModel: AirPodsModel = .airPodsPro2

    // State for Calibration Sheet
    @State private var isShowingCalibratorSheet: Bool = false
    @State private var isCase3DMode: Bool = false

    private var currentFrame: DeviceContinuityFrame {
        continuityDecoder.latestFrame ?? DeviceContinuityFrame(
            model: spoofedModel,
            leftBattery: EarbudBatteryState(percentage: 85, isCharging: false),
            rightBattery: EarbudBatteryState(percentage: 90, isCharging: false),
            caseBattery: EarbudBatteryState(percentage: 100, isCharging: false),
            leftInEar: true,
            rightInEar: true,
            primaryMicIsLeft: true,
            lidOpenCount: 1,
            rssi: -58,
            smoothedRSSI: -58.0,
            isNearProximity: true
        )
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Top Header: Device Name & Spoofer Button
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(spoofedDeviceName)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            Button(action: {
                                isShowingDeviceSpoofer = true
                            }) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("Serial: \(spoofedSerialNumber) • \(currentFrame.model.badgeName)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Connection Indicator Badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(gattClient.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)

                        Text(gattClient.isConnected ? "GATT Active" : "Continuity")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                // 3D Procedural Earbud Model Card
                VStack(spacing: 10) {
                    ZStack(alignment: .topTrailing) {
                        AirPods3DView(isCaseMode: isCase3DMode, isCharging: currentFrame.caseBattery.isCharging)
                            .frame(height: 195)

                        // 3D Switch Mode (Earbuds vs Case)
                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            isCase3DMode.toggle()
                        }) {
                            Label(isCase3DMode ? "Earbuds" : "Case", systemImage: isCase3DMode ? "airpodspro" : "airpodspro.chargingcase.wireless")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial)
                                .clipShape(Capsule())
                        }
                        .padding(12)
                    }

                    // Battery Horizontal Pill Cards
                    HStack(spacing: 12) {
                        BatteryStatusCard(
                            title: "Left",
                            icon: "airpodspro.left",
                            battery: currentFrame.leftBattery
                        )
                        BatteryStatusCard(
                            title: "Case",
                            icon: "airpodspro.chargingcase.wireless",
                            battery: currentFrame.caseBattery
                        )
                        BatteryStatusCard(
                            title: "Right",
                            icon: "airpodspro.right",
                            battery: currentFrame.rightBattery
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                // Native iOS Noise Control Segmented Pill
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("NOISE CONTROL")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        Spacer()

                        if dspProcessor.isConversationActive {
                            HStack(spacing: 4) {
                                Image(systemName: "person.wave.2.fill")
                                    .font(.system(size: 10))
                                Text("Speech Detected (Ducked)")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 0) {
                        ForEach(NoiseControlMode.allCases) { mode in
                            NoiseModePillItem(
                                mode: mode,
                                isSelected: dspProcessor.currentNoiseMode == mode
                            ) {
                                selectNoiseMode(mode)
                            }
                        }
                    }
                    .padding(5)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 16)

                // Live vDSP FFT Spectrum Visualizer Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ACOUSTIC SPECTRUM & AMBIENT NOISE")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            Text(String(format: "Ambient Sound Level: %.1f dB SPL", dspProcessor.ambientSPLdB))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        // Calibrate Button
                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            isShowingCalibratorSheet = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform.badge.magnifyingglass")
                                Text("Calibrate")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }

                    // 24-Band FFT Bars
                    HStack(alignment: .bottom, spacing: 3.5) {
                        ForEach(0..<dspProcessor.frequencySpectrum.count, id: \.self) { index in
                            let height = max(4.0, CGFloat(dspProcessor.frequencySpectrum[index]) * 55.0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.cyan, Color.blue],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: height)
                        }
                    }
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                // Quick Clone Hardware Actions
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        // Auto-Detect Hardware ANC Probe
                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            gattClient.autoDetectHardwareANC()
                        }) {
                            HStack {
                                Image(systemName: "cpu")
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto-Detect ANC")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(gattClient.isProbing ? "Probing GATT..." : (gattClient.detectedChipsetName ?? "Tap to Identify"))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .foregroundColor(.primary)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        // Safety Lock Status
                        Button(action: {
                            HapticFeedbackManager.shared.warning()
                        }) {
                            HStack {
                                Image(systemName: gattClient.isBrickingSafetyLockEngaged ? "lock.shield.fill" : "exclamationmark.shield.fill")
                                    .foregroundColor(gattClient.isBrickingSafetyLockEngaged ? .green : .red)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Safety Lock")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Anti-Bricking Active")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .foregroundColor(.primary)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $isShowingDeviceSpoofer) {
            DeviceSpooferSheet(
                deviceName: $spoofedDeviceName,
                serialNumber: $spoofedSerialNumber,
                selectedModel: $spoofedModel
            )
        }
        .sheet(isPresented: $isShowingCalibratorSheet) {
            AcousticCalibratorSheet(calibrator: calibrator)
        }
    }

    private func selectNoiseMode(_ mode: NoiseControlMode) {
        HapticFeedbackManager.shared.modeChanged()
        AudioChimeSynthesizer.shared.playModeSwitchChime(for: mode)
        dspProcessor.setNoiseMode(mode)
        gattClient.sendNoiseMode(mode)
    }
}

// MARK: - Subcomponents

private struct NoiseModePillItem: View {
    let mode: NoiseControlMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 18, weight: isSelected ? .bold : .regular))

                Text(mode.title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected ?
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                    : nil
            )
        }
    }
}

private struct BatteryStatusCard: View {
    let title: String
    let icon: String
    let battery: EarbudBatteryState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 2) {
                    if let pct = battery.percentage {
                        Text("\(pct)%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    } else {
                        Text("—")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    }

                    if battery.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Device Spoofer Sheet

private struct DeviceSpooferSheet: View {
    @Binding var deviceName: String
    @Binding var serialNumber: String
    @Binding var selectedModel: AirPodsModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Device Identity Spoofer")) {
                    TextField("Device Name", text: $deviceName)
                    TextField("Serial Number", text: $serialNumber)
                }

                Section(header: Text("Spoofed Hardware Model")) {
                    Picker("Model Badge", selection: $selectedModel) {
                        ForEach(AirPodsModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                }

                Section(footer: Text("Custom identities are mirrored across Apple Continuity broadcast listeners and Gestalt interfaces.")) {
                    Button("Save Identity") {
                        HapticFeedbackManager.shared.pairingSuccess()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Device Spoofer")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

// MARK: - Acoustic Calibrator Sheet

private struct AcousticCalibratorSheet: View {
    @ObservedObject var calibrator: AutoLatencyCalibrator
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)

                    Text("Acoustic Latency Wizard")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("Emits a 60ms logarithmic test chirp to synchronize vDSP anti-noise phase delay with your earbud's exact A2DP latency.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 16)

                // Calibration Progress Bar
                if calibrator.isCalibrating {
                    VStack(spacing: 8) {
                        ProgressView(value: calibrator.calibrationProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            .padding(.horizontal, 32)

                        Text(calibrator.statusMessage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }

                // Measured Latency Display
                VStack(spacing: 6) {
                    Text(String(format: "%.1f ms", calibrator.effectiveTotalDelayMs))
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Locked Round-Trip Phase Delay")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 24)

                // Manual Fine-Tune Slider (0ms to 250ms)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Manual Phase Offset:")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(String(format: "%+.1f ms", calibrator.manualFineTuneOffsetMs))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }

                    Slider(value: $calibrator.manualFineTuneOffsetMs, in: -40.0...40.0, step: 0.5)
                        .tint(.blue)
                }
                .padding(.horizontal, 24)

                Spacer()

                Button(action: {
                    HapticFeedbackManager.shared.buttonTap()
                    calibrator.startCalibration()
                }) {
                    Text(calibrator.isCalibrating ? "Calibrating..." : "Start 3-Second Calibration")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(calibrator.isCalibrating ? Color.gray : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(calibrator.isCalibrating)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .navigationBarItems(trailing: Button("Close") { dismiss() })
        }
    }
}

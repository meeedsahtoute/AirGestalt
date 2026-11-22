//
//  DashboardView.swift
//  AirGestalt
//
//  Main Apple Gestalt Control Center.
//  Features a pinned status-safe blurred header, interactive Auto-Detect ANC scanner,
//  segmented noise control pill with real hardware GATT + software passthrough,
//  live vDSP FFT spectrum visualizer, zero-mock battery indicators, and persistent spoofer.
//

import SwiftUI
import AVFoundation

public struct DashboardView: View {
    @ObservedObject var continuityDecoder = ContinuityDecoder.shared
    @ObservedObject var gattClient = CloneGATTClient.shared
    @ObservedObject var dspProcessor = VDSPAntiNoiseProcessor.shared
    @ObservedObject var calibrator = AutoLatencyCalibrator.shared
    @ObservedObject var audioEngine = GhostAudioEngine.shared

    // Persistent State for Custom Device Spoofer
    @AppStorage("com.airgestalt.spoofedDeviceName") private var spoofedDeviceName: String = "AirPods Pro 2"
    @AppStorage("com.airgestalt.spoofedSerialNumber") private var spoofedSerialNumber: String = "H7J2L90PQ4"
    @AppStorage("com.airgestalt.spoofedModelCode") private var spoofedModelRaw: Int = Int(AirPodsModel.airPodsPro2.rawCode)

    // State for Sheets & UI modes
    @State private var isShowingDeviceSpoofer: Bool = false
    @State private var isShowingCalibratorSheet: Bool = false
    @State private var isShowingScannerSheet: Bool = false
    @State private var showOfflineToast: Bool = false
    @State private var isCase3DMode: Bool = false

    private var spoofedModel: AirPodsModel {
        AirPodsModel.from(rawModelCode: UInt16(spoofedModelRaw))
    }

    private var leftBatteryState: EarbudBatteryState {
        if let pct = continuityDecoder.latestFrame?.leftBattery.percentage {
            return EarbudBatteryState(percentage: pct, isCharging: continuityDecoder.latestFrame?.leftBattery.isCharging ?? false)
        }
        if let gattPct = gattClient.gattLeftBattery {
            return EarbudBatteryState(percentage: gattPct, isCharging: false)
        }
        return EarbudBatteryState(percentage: nil, isCharging: false)
    }

    private var rightBatteryState: EarbudBatteryState {
        if let pct = continuityDecoder.latestFrame?.rightBattery.percentage {
            return EarbudBatteryState(percentage: pct, isCharging: continuityDecoder.latestFrame?.rightBattery.isCharging ?? false)
        }
        if let gattPct = gattClient.gattRightBattery {
            return EarbudBatteryState(percentage: gattPct, isCharging: false)
        }
        return EarbudBatteryState(percentage: nil, isCharging: false)
    }

    private var caseBatteryState: EarbudBatteryState {
        if let pct = continuityDecoder.latestFrame?.caseBattery.percentage {
            return EarbudBatteryState(percentage: pct, isCharging: continuityDecoder.latestFrame?.caseBattery.isCharging ?? false)
        }
        if let gattPct = gattClient.gattCaseBattery {
            return EarbudBatteryState(percentage: gattPct, isCharging: false)
        }
        return EarbudBatteryState(percentage: nil, isCharging: false)
    }

    private var currentFrame: DeviceContinuityFrame {
        continuityDecoder.latestFrame ?? DeviceContinuityFrame(
            model: spoofedModel,
            leftBattery: leftBatteryState,
            rightBattery: rightBatteryState,
            caseBattery: caseBatteryState,
            leftInEar: false,
            rightInEar: false,
            primaryMicIsLeft: false,
            lidOpenCount: 0,
            rssi: -100,
            smoothedRSSI: -100.0,
            isNearProximity: false
        )
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Ghost Mode Active Glowing Indicator Badge
                if audioEngine.isGhostModeActive || audioEngine.isSoftwareTransparencyActive {
                    ghostModeBanner
                }

                // 3D Procedural Earbud Model Card
                VStack(spacing: 10) {
                    ZStack(alignment: .topTrailing) {
                        AirPods3DView(isCaseMode: isCase3DMode, isCharging: caseBatteryState.isCharging)
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

                    // Battery Horizontal Pill Cards (Zero-Mock: Shows "—" when disconnected)
                    HStack(spacing: 12) {
                        BatteryStatusCard(
                            title: "Left",
                            icon: "airpodspro.left",
                            battery: leftBatteryState
                        )
                        BatteryStatusCard(
                            title: "Case",
                            icon: "airpodspro.chargingcase.wireless",
                            battery: caseBatteryState
                        )
                        BatteryStatusCard(
                            title: "Right",
                            icon: "airpodspro.right",
                            battery: rightBatteryState
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
                .padding(.top, 8)

                // BLE Offline Warning Banner (Shown if ANC tapped while disconnected)
                if showOfflineToast && !gattClient.isConnected {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 15))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("BLE Offline: Earbud Disconnected")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                            Text("Connect earbud to send hardware ANC commands.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            isShowingScannerSheet = true
                        }) {
                            Text("Connect")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }

                        Button(action: {
                            withAnimation {
                                showOfflineToast = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(4)
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Native iOS Noise Control Segmented Pill
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("NOISE CONTROL")
                            .font(.system(size: 11, weight: .semibold))
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

                    // Real-Time Hardware GATT / Passthrough Status Line
                    HStack(spacing: 6) {
                        Circle()
                            .fill(gattClient.isConnected ? Color.green : Color.blue)
                            .frame(width: 6, height: 6)

                        Text(gattClient.lastGATTStatus)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer()

                        if audioEngine.isSoftwareTransparencyActive {
                            Text("Software Passthrough ON")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)

                // Live vDSP FFT Spectrum Visualizer Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ACOUSTIC SPECTRUM & AMBIENT NOISE")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            if audioEngine.isAmbientMonitoringActive && dspProcessor.ambientSPLdB > 10.0 {
                                Text(String(format: "Ambient Sound Level: %.1f dB SPL", dspProcessor.ambientSPLdB))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            } else {
                                Text(audioEngine.isAmbientMonitoringActive ? "Ambient Sound Level: Listening..." : "Ambient Sound Level: Inactive")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Explicit Live Ambient Monitoring Toggle Button
                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            let newActive = !audioEngine.isAmbientMonitoringActive
                            audioEngine.setAmbientMonitoringActive(newActive)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: audioEngine.isAmbientMonitoringActive ? "stop.fill" : "waveform.badge.mic")
                                Text(audioEngine.isAmbientMonitoringActive ? "Stop" : "Monitor")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(audioEngine.isAmbientMonitoringActive ? .white : .blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(audioEngine.isAmbientMonitoringActive ? Color.red : Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                        }

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
                        // Interactive Auto-Detect Hardware ANC Probe Button
                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            gattClient.startAutoDetectANCScan()
                        }) {
                            HStack(spacing: 10) {
                                if gattClient.isDetectingChipset || gattClient.isProbing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                        .frame(width: 22, height: 22)
                                } else {
                                    Image(systemName: "cpu")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto-Detect ANC")
                                        .font(.system(size: 13, weight: .bold))

                                    Text(gattClient.isDetectingChipset ? "Scanning BLE..." : (gattClient.detectedChipsetName ?? "Tap to Identify"))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        // Safety Lock Interactive Toggle
                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            gattClient.isBrickingSafetyLockEngaged.toggle()
                        }) {
                            HStack {
                                Image(systemName: gattClient.isBrickingSafetyLockEngaged ? "lock.shield.fill" : "exclamationmark.shield.fill")
                                    .foregroundColor(gattClient.isBrickingSafetyLockEngaged ? .green : .red)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Safety Lock")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(gattClient.isBrickingSafetyLockEngaged ? "Anti-Bricking Active" : "Bypassed (Warning)")
                                        .font(.system(size: 10))
                                        .foregroundColor(gattClient.isBrickingSafetyLockEngaged ? .secondary : .red)
                                }
                                Spacer()
                                Image(systemName: gattClient.isBrickingSafetyLockEngaged ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(gattClient.isBrickingSafetyLockEngaged ? .green : .red)
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
        // Pin Header to Top Safe Area to prevent scroll collision in LiveContainer
        .safeAreaInset(edge: .top) {
            pinnedHeaderView
        }
        .sheet(isPresented: $isShowingDeviceSpoofer) {
            DeviceSpooferSheet(
                deviceName: $spoofedDeviceName,
                serialNumber: $spoofedSerialNumber,
                selectedModelRaw: $spoofedModelRaw
            )
        }
        .sheet(isPresented: $isShowingCalibratorSheet) {
            AcousticCalibratorSheet(calibrator: calibrator)
        }
        .sheet(isPresented: $isShowingScannerSheet) {
            BLEScannerView()
        }
        .sheet(isPresented: $gattClient.showDetectionSheet) {
            ChipsetDetectionSheet(gattClient: gattClient, audioEngine: audioEngine)
        }
    }

    // MARK: - Pinned Safe-Area Header View

    private var pinnedHeaderView: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                // Subtle Brand Vector Emblem (Matching Acoustic Wave + AirPods icon)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 10/255, green: 13/255, blue: 20/255), Color(red: 20/255, green: 27/255, blue: 45/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.cyan.opacity(0.85), Color.blue.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(color: Color.cyan.opacity(0.25), radius: 4, x: 0, y: 0)

                    Image(systemName: "airpodspro")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(audioEngine.activeOutputDeviceName)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Button(action: {
                            isShowingDeviceSpoofer = true
                        }) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(audioEngine.activeRouteConnectionType)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)

                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)

                        Text("\(audioEngine.currentSampleRateString) • ID: \(audioEngine.activeRouteUID)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Interactive Connection Indicator Badge / Scanner Opener
            Button(action: {
                HapticFeedbackManager.shared.buttonTap()
                isShowingScannerSheet = true
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(gattClient.isConnected ? Color.green : (gattClient.isConnecting ? Color.orange : Color.blue))
                        .frame(width: 8, height: 8)

                    Text(gattClient.isConnected ? (gattClient.connectedPeripheralName ?? "Connected ✓") : (gattClient.isConnecting ? "Connecting..." : "Scan & Connect"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(gattClient.isConnected ? .green : .primary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(gattClient.isConnected ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
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

    // MARK: - Ghost Mode Active Indicator Card

    private var ghostModeBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 10, height: 10)
                Circle()
                    .stroke(Color.cyan.opacity(0.4), lineWidth: 4)
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("GHOST MODE ACTIVE")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.cyan)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(audioEngine.isSoftwareTransparencyActive ? "Software Transparency ON" : "Background DSP Engine")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Text("Ultra-low latency DSP (5ms) • 10-Band Live EQ • Background Audio Session")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                HapticFeedbackManager.shared.buttonTap()
                audioEngine.setGhostModeActive(false)
                audioEngine.setTransparencyActive(false)
            }) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                    .padding(6)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 10/255, green: 20/255, blue: 32/255))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.cyan.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: Color.cyan.opacity(0.25), radius: 6, x: 0, y: 0)
        )
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func selectNoiseMode(_ mode: NoiseControlMode) {
        HapticFeedbackManager.shared.modeChanged()
        dspProcessor.setNoiseMode(mode)

        if !gattClient.isConnected {
            withAnimation {
                showOfflineToast = true
            }
        } else {
            withAnimation {
                showOfflineToast = false
            }
        }

        // Send hardware GATT command to clone earbuds if connected
        gattClient.sendNoiseMode(mode)

        // Real Software Transparency:
        // When Transparency is selected, route iPhone microphone -> 10-band EQ -> Varispeed -> earbuds
        if mode == .transparency {
            audioEngine.setTransparencyActive(true)
        } else {
            if audioEngine.isSoftwareTransparencyActive {
                audioEngine.setTransparencyActive(false)
            }
        }

        // Play authentic Apple-style mode switch chime
        AudioChimeSynthesizer.shared.playModeSwitchChime(for: mode)
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text("—")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
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

// MARK: - Interactive Chipset Detection Sheet

private struct ChipsetDetectionSheet: View {
    @ObservedObject var gattClient: CloneGATTClient
    @ObservedObject var audioEngine: GhostAudioEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Header Banner
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 58, height: 58)

                        if gattClient.isDetectingChipset || gattClient.isProbing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        } else {
                            Image(systemName: "cpu")
                                .font(.system(size: 26))
                                .foregroundColor(.blue)
                        }
                    }

                    Text("Auto-Detect Hardware ANC")
                        .font(.system(size: 19, weight: .bold, design: .rounded))

                    Text(gattClient.detectionStatusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 12)

                // Active iOS Audio Route Indicator Card
                HStack(spacing: 10) {
                    Image(systemName: "headphones")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("ACTIVE AUDIO ROUTE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Text(audioEngine.activeOutputDeviceName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 15))
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)

                // Currently Active / Identified Profile Card
                if let profile = gattClient.activeProfile {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ACTIVE CHIPSET PROFILE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(profile.vendor.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.blue)
                        }

                        Text(profile.name)
                            .font(.system(size: 14, weight: .bold))

                        HStack(spacing: 8) {
                            CapabilityPill(title: "Hardware ANC", isSupported: !profile.ancOnHex.isEmpty)
                            CapabilityPill(title: "Transparency", isSupported: !profile.transparencyHex.isEmpty)
                            CapabilityPill(title: "Hardware EQ", isSupported: profile.eqBassBoostHex != nil)
                        }
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                }

                // Discovered Clone Devices List & Filter Control
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("NEARBY BLE ACCESSORIES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()

                        Toggle("Show TVs & Clutter", isOn: $gattClient.showAllDevices)
                            .font(.system(size: 11))
                            .labelsHidden()

                        Text(gattClient.showAllDevices ? "All Devices" : "Filtered")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(gattClient.showAllDevices ? .orange : .secondary)
                    }
                    .padding(.horizontal, 18)

                    if gattClient.discoveredCloneDevices.isEmpty {
                        VStack(spacing: 8) {
                            Text(gattClient.isDetectingChipset ? "Searching for clone earbuds..." : "No earbud discovered.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)

                            Button("Scan Nearby Devices") {
                                HapticFeedbackManager.shared.buttonTap()
                                gattClient.startAutoDetectANCScan()
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        List(gattClient.discoveredCloneDevices) { device in
                            Button(action: {
                                HapticFeedbackManager.shared.buttonTap()
                                gattClient.connect(to: device.peripheral)
                            }) {
                                HStack {
                                    Image(systemName: "airpodspro")
                                        .font(.system(size: 18))
                                        .foregroundColor(.primary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.primary)

                                        HStack(spacing: 6) {
                                            if let vendor = device.probableVendor {
                                                Text(vendor.rawValue)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(.blue)
                                            }
                                            Text("\(device.rssi) dBm")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if gattClient.isConnecting && gattClient.connectedPeripheralName == device.name {
                                        ProgressView()
                                            .frame(width: 24, height: 24)
                                    } else if gattClient.isConnected && gattClient.connectedPeripheralName == device.name {
                                        Text("Connected")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Connect")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.blue)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                }

                Spacer()
            }
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

private struct CapabilityPill: View {
    let title: String
    let isSupported: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isSupported ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 9))
                .foregroundColor(isSupported ? .green : .secondary)

            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSupported ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Device Spoofer Sheet

private struct DeviceSpooferSheet: View {
    @Binding var deviceName: String
    @Binding var serialNumber: String
    @Binding var selectedModelRaw: Int
    @Environment(\.dismiss) var dismiss

    private var selectedModelBinding: Binding<AirPodsModel> {
        Binding(
            get: { AirPodsModel.from(rawModelCode: UInt16(selectedModelRaw)) },
            set: { selectedModelRaw = Int($0.rawCode) }
        )
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Device Identity Spoofer")) {
                    TextField("Device Name", text: $deviceName)
                    TextField("Serial Number", text: $serialNumber)
                }

                Section(header: Text("Spoofed Hardware Model")) {
                    Picker("Model Badge", selection: selectedModelBinding) {
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

                // Manual Fine-Tune Slider (-40ms to +40ms)
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

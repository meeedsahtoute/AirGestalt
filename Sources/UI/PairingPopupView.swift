//
//  PairingPopupView.swift
//  AirGestalt
//
//  Apple Proximity Pairing Modal with Spring Animations,
//  Circular Battery Rings (Left, Right, Case), 3D Preview, and Haptic Feedback.
//

import SwiftUI

public struct PairingPopupView: View {
    @ObservedObject var continuityDecoder: ContinuityDecoder
    @Binding var isPresented: Bool

    @State private var appearOffset: CGFloat = 400
    @State private var ringAnimation: Double = 0.0

    public init(continuityDecoder: ContinuityDecoder, isPresented: Binding<Bool>) {
        self.continuityDecoder = continuityDecoder
        self._isPresented = isPresented
    }

    private var frame: DeviceContinuityFrame {
        continuityDecoder.latestFrame ?? DeviceContinuityFrame(
            model: .airPodsPro2,
            leftBattery: EarbudBatteryState(percentage: 80, isCharging: false),
            rightBattery: EarbudBatteryState(percentage: 90, isCharging: false),
            caseBattery: EarbudBatteryState(percentage: 100, isCharging: true),
            leftInEar: true,
            rightInEar: true,
            primaryMicIsLeft: true,
            lidOpenCount: 1,
            rssi: -50,
            smoothedRSSI: -50.0,
            isNearProximity: true
        )
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Semi-transparent background backdrop
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissModal()
                }

            // Bottom-sheet Card
            VStack(spacing: 16) {
                // Drag handle
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)

                // Model Title & Badge
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(frame.model.displayName)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text(frame.model.badgeName)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }

                    Text("Connected via Apple Continuity Protocol (0x004C)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // 3D SceneKit Earbuds View
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .frame(height: 180)

                    AirPods3DView(isCaseMode: false, isCharging: frame.caseBattery.isCharging)
                        .frame(height: 175)
                }
                .padding(.horizontal, 8)

                // Battery Status Rings (Left, Case, Right)
                HStack(spacing: 24) {
                    // Left Earbud Ring
                    BatteryRingItem(
                        title: "Left",
                        icon: "airpodspro.left",
                        battery: frame.leftBattery,
                        progress: ringAnimation
                    )

                    // Case Ring
                    BatteryRingItem(
                        title: "Case",
                        icon: "airpodspro.chargingcase.wireless",
                        battery: frame.caseBattery,
                        progress: ringAnimation
                    )

                    // Right Earbud Ring
                    BatteryRingItem(
                        title: "Right",
                        icon: "airpodspro.right",
                        battery: frame.rightBattery,
                        progress: ringAnimation
                    )
                }
                .padding(.vertical, 6)

                // Action Button
                Button(action: {
                    HapticFeedbackManager.shared.pairingSuccess()
                    dismissModal()
                }) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.2), radius: 25, x: 0, y: -5)
            )
            .offset(y: appearOffset)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                appearOffset = 0
            }
            withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
                ringAnimation = 1.0
            }
            HapticFeedbackManager.shared.pairingSuccess()
        }
    }

    private func dismissModal() {
        withAnimation(.easeIn(duration: 0.25)) {
            appearOffset = 500
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            continuityDecoder.dismissPairingPopup()
            isPresented = false
        }
    }
}

// MARK: - Battery Ring Component

private struct BatteryRingItem: View {
    let title: String
    let icon: String
    let battery: EarbudBatteryState
    let progress: Double

    private var percentage: Int {
        battery.percentage ?? 0
    }

    private var normalizedRatio: CGFloat {
        CGFloat(percentage) / 100.0 * CGFloat(progress)
    }

    private var ringColor: Color {
        if battery.isCharging {
            return .orange
        } else if percentage > 20 {
            return .green
        } else {
            return .red
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 4.5)
                    .frame(width: 58, height: 58)

                // Animated Circular Ring
                Circle()
                    .trim(from: 0, to: normalizedRatio)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(-90))

                // Center Icon / Charging Indicator
                VStack(spacing: 1) {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)

                    if battery.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                }
            }

            // Percentage Label
            if let pct = battery.percentage {
                Text("\(pct)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            } else {
                Text("—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
            }

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

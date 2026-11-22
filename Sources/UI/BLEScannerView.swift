//
//  BLEScannerView.swift
//  AirGestalt
//
//  Interactive Bluetooth Low Energy Scanner & Connection Coordinator.
//  Sorts discovered peripherals by RSSI (strongest first), displays vendor identification,
//  includes a Show All Devices filter toggle, and connects clone earbuds in 1 tap.
//

import SwiftUI
import CoreBluetooth

public struct BLEScannerView: View {
    @ObservedObject var gattClient = CloneGATTClient.shared
    @Environment(\.dismiss) var dismiss

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status & Controls Header Bar
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        if gattClient.isDetectingChipset {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                .frame(width: 20, height: 20)
                        } else {
                            Circle()
                                .fill(gattClient.isConnected ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(gattClient.isDetectingChipset ? "Scanning BLE Frequencies..." : (gattClient.isConnected ? "Connected to \(gattClient.connectedPeripheralName ?? "Earbud")" : "Scanner Ready"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)

                            Text(gattClient.lastGATTStatus)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            if gattClient.isDetectingChipset {
                                gattClient.stopScan()
                            } else {
                                gattClient.startScanning()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: gattClient.isDetectingChipset ? "stop.fill" : "arrow.clockwise")
                                Text(gattClient.isDetectingChipset ? "Stop" : "Rescan")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(gattClient.isDetectingChipset ? Color.red : Color.blue)
                            .clipShape(Capsule())
                        }
                    }

                    Divider()

                    // Filter & Device Count Row
                    HStack {
                        Text("\(gattClient.discoveredCloneDevices.count) device(s) found")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        Spacer()

                        Toggle("Show All Devices", isOn: $gattClient.showAllDevices)
                            .font(.system(size: 12, weight: .medium))
                            .labelsHidden()

                        Text(gattClient.showAllDevices ? "All Devices (Unfiltered)" : "Clone Filter Active")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(gattClient.showAllDevices ? .orange : .secondary)
                    }
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemBackground))

                // Discovered Devices List
                if gattClient.discoveredCloneDevices.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()

                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 48))
                            .foregroundColor(.blue.opacity(0.8))

                        Text("No Earbuds Discovered")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Troubleshooting Tips:")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.primary)

                            HStack(alignment: .top, spacing: 6) {
                                Text("1.")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Open earbud case lid or put earbuds in your ears.")
                                    .font(.system(size: 12))
                            }
                            HStack(alignment: .top, spacing: 6) {
                                Text("2.")
                                    .font(.system(size: 12, weight: .bold))
                                Text("If already playing music in iOS Settings, tap 'Rescan' to detect the active iOS route.")
                                    .font(.system(size: 12))
                            }
                            HStack(alignment: .top, spacing: 6) {
                                Text("3.")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Toggle 'All Devices (Unfiltered)' above if clone earbud advertises without a name.")
                                    .font(.system(size: 12))
                            }
                        }
                        .foregroundColor(.secondary)
                        .padding(16)
                        .background(Color(uiColor: .tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 24)

                        Button("Start BLE Scan") {
                            HapticFeedbackManager.shared.buttonTap()
                            gattClient.startScanning()
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .clipShape(Capsule())

                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        ForEach(gattClient.discoveredCloneDevices) { device in
                            DiscoveredDeviceRow(
                                device: device,
                                isConnecting: gattClient.isConnecting && gattClient.currentTargetPeripheral?.identifier == device.peripheral.identifier,
                                isConnected: gattClient.isConnected && gattClient.currentTargetPeripheral?.identifier == device.peripheral.identifier
                            ) {
                                HapticFeedbackManager.shared.buttonTap()
                                gattClient.connect(to: device.peripheral)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("BLE Earbud Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .onAppear {
            if !gattClient.isConnected {
                gattClient.startScanning()
            }
        }
    }
}

private struct DiscoveredDeviceRow: View {
    let device: DiscoveredCloneDevice
    let isConnecting: Bool
    let isConnected: Bool
    let onConnect: () -> Void

    private var displayName: String {
        if !device.name.isEmpty && device.name != "Bluetooth Audio Accessory" {
            return device.name
        }
        let shortUUID = String(device.peripheral.identifier.uuidString.prefix(6))
        return "Unknown BLE Device (\(shortUUID))"
    }

    private var rssiColor: Color {
        if device.rssi >= -65 { return .green }
        if device.rssi >= -80 { return .yellow }
        return .orange
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 44, height: 44)

                Image(systemName: "airpodspro")
                    .font(.system(size: 20))
                    .foregroundColor(isConnected ? .green : .blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let vendor = device.probableVendor {
                        Text(vendor.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 3) {
                        Circle()
                            .fill(rssiColor)
                            .frame(width: 6, height: 6)

                        Text("\(device.rssi) dBm")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Text("ID: \(String(device.peripheral.identifier.uuidString.prefix(4)))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            Spacer()

            if isConnecting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .frame(width: 32, height: 32)
            } else if isConnected {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Paired")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            } else {
                Button(action: onConnect) {
                    Text("Connect")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

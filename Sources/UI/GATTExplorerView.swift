//
//  GATTExplorerView.swift
//  AirGestalt
//
//  Live GATT Packet Diffing Lab & Community Profile Exporter View.
//  Records stem-toggle triggers, visually highlights changed hex delta bytes,
//  and exports clean JSON profiles ready for open-source GitHub pull requests.
//

import SwiftUI
import UniformTypeIdentifiers

public struct GATTExplorerView: View {
    @ObservedObject var diffEngine = PacketDiffEngine.shared
    @ObservedObject var gattClient = CloneGATTClient.shared

    @State private var customHexInput: String = ""
    @State private var exportVendor: ChipsetVendor = .airoha
    @State private var exportChipsetName: String = "AB1562A"
    @State private var isShowingExportSheet: Bool = false
    @State private var copyConfirmation: Bool = false

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 4) {
                    Text("Live GATT Diffing Lab")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Reverse-engineer clone ANC stems & export GitHub-ready JSON profiles")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 10)

                // Recording Control Bar Card
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RECORD DIFF SESSION")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            Text(diffEngine.isRecording ? "Recording stem press events..." : "\(diffEngine.recordedPackets.count) packets captured")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(diffEngine.isRecording ? .red : .primary)
                        }

                        Spacer()

                        // Record Toggle
                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            if diffEngine.isRecording {
                                diffEngine.stopRecording()
                            } else {
                                diffEngine.startRecording()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(diffEngine.isRecording ? Color.red : Color.red)
                                    .frame(width: 10, height: 10)

                                Text(diffEngine.isRecording ? "Stop & Diff" : "Record Diff")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(diffEngine.isRecording ? Color.red : Color.blue)
                            .clipShape(Capsule())
                        }
                    }

                    if !diffEngine.recordedPackets.isEmpty {
                        HStack {
                            Button("Clear All") {
                                HapticFeedbackManager.shared.buttonTap()
                                diffEngine.clearAll()
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                            Spacer()

                            Button(action: {
                                HapticFeedbackManager.shared.buttonTap()
                                _ = diffEngine.exportAsCommunityProfileJSON(
                                    vendor: exportVendor,
                                    chipsetName: exportChipsetName
                                )
                                isShowingExportSheet = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export Profile JSON")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
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

                // Highlighted Delta Diff Result Card
                if let diff = diffEngine.currentDiff {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text("DETECTED STEM TOGGLE DELTA")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        Text(diff.explanation)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Divider()

                        // Baseline Payload with highlights
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Baseline (Prior State):")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            HighlightedHexView(
                                rawBytes: diff.baseline.rawBytes,
                                highlightedIndices: diff.deltaIndices,
                                highlightColor: .orange
                            )
                        }

                        // Active Payload with highlights
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active (Post-Stem Press):")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            HighlightedHexView(
                                rawBytes: diff.active.rawBytes,
                                highlightedIndices: diff.deltaIndices,
                                highlightColor: .green
                            )
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.purple.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                }

                // Custom Hex Command Sender & Safety Lock Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("MANUAL GATT HEX INJECTOR")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack {
                        TextField("e.g. 055A0400060A0101", text: $customHexInput)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .disableAutocorrection(true)
                            .padding(10)
                            .background(Color(uiColor: .tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button(action: {
                            HapticFeedbackManager.shared.buttonTap()
                            do {
                                try gattClient.sendCustomHex(customHexInput)
                            } catch {
                                HapticFeedbackManager.shared.error()
                                print("Inject error: \(error)")
                            }
                        }) {
                            Text("Send")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    if let lastSent = gattClient.lastSentHex {
                        HStack(spacing: 4) {
                            Text("Last TX:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(lastSent)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 16)

                // Captured Packet Stream List
                VStack(alignment: .leading, spacing: 10) {
                    Text("PACKET CAPTURE STREAM")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    if diffEngine.recordedPackets.isEmpty {
                        Text("No packets captured yet. Tap 'Record Diff' and press the earbud stem or send a command.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(diffEngine.recordedPackets.reversed()) { packet in
                            PacketRowView(packet: packet)
                        }
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
        .sheet(isPresented: $isShowingExportSheet) {
            ProfileExportSheet(
                vendor: $exportVendor,
                chipsetName: $exportChipsetName,
                jsonContent: diffEngine.generatedJSONProfile ?? "{}"
            )
        }
    }
}

// MARK: - Subcomponents

private struct HighlightedHexView: View {
    let rawBytes: [UInt8]
    let highlightedIndices: [Int]
    let highlightColor: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<rawBytes.count, id: \.self) { idx in
                let byte = rawBytes[idx]
                let isDelta = highlightedIndices.contains(idx)

                Text(String(format: "%02X", byte))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(isDelta ? highlightColor.opacity(0.3) : Color.clear)
                    .foregroundColor(isDelta ? highlightColor : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }
}

private struct PacketRowView: View {
    let packet: GATTPacketRecord

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(packet.direction == .tx ? "TX" : "RX")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(packet.direction == .tx ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                .foregroundColor(packet.direction == .tx ? .blue : .green)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(packet.payloadHex)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)

                Text("Char: \(packet.charUUID)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(packet.timestamp, style: .time)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileExportSheet: View {
    @Binding var vendor: ChipsetVendor
    @Binding var chipsetName: String
    let jsonContent: String
    @Environment(\.dismiss) var dismiss
    @State private var didCopy: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Chipset Metadata")) {
                    Picker("Vendor", selection: $vendor) {
                        ForEach(ChipsetVendor.allCases) { v in
                            Text(v.rawValue).tag(v)
                        }
                    }

                    TextField("Chipset Name", text: $chipsetName)
                }

                Section(header: Text("Community Profile JSON (For GitHub PR)")) {
                    Text(jsonContent)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)

                    Button(action: {
                        UIPasteboard.general.string = jsonContent
                        HapticFeedbackManager.shared.pairingSuccess()
                        didCopy = true
                    }) {
                        HStack {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            Text(didCopy ? "Copied to Clipboard!" : "Copy JSON to Clipboard")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Export Chipset Profile")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

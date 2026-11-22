//
//  PacketDiffEngine.swift
//  AirGestalt
//
//  Live GATT Packet Diffing Lab & Community Profile Exporter.
//  Records baseline vs active packets (e.g. stem-toggle triggers),
//  detects modified hex bytes, and exports ready-to-share JSON chipset profiles.
//

import Foundation
import Combine

public final class PacketDiffEngine: ObservableObject {
    public static let shared = PacketDiffEngine()

    // MARK: - Published State
    @Published public var isRecording: Bool = false
    @Published public var recordedPackets: [GATTPacketRecord] = []
    @Published public var baselinePacket: GATTPacketRecord? = nil
    @Published public var activePacket: GATTPacketRecord? = nil
    @Published public var currentDiff: PacketDiffResult? = nil
    @Published public var generatedJSONProfile: String? = nil

    private var cancellables = Set<AnyCancellable>()

    public init() {
        // Wire up packet capture callback from CloneGATTClient
        CloneGATTClient.shared.onPacketCaptured = { [weak self] packet in
            self?.recordPacket(packet)
        }
    }

    // MARK: - Recording Controls

    public func startRecording() {
        recordedPackets.removeAll()
        baselinePacket = nil
        activePacket = nil
        currentDiff = nil
        generatedJSONProfile = nil
        isRecording = true
    }

    public func stopRecording() {
        isRecording = false
        analyzeRecordedPackets()
    }

    public func clearAll() {
        isRecording = false
        recordedPackets.removeAll()
        baselinePacket = nil
        activePacket = nil
        currentDiff = nil
        generatedJSONProfile = nil
    }

    public func recordPacket(_ packet: GATTPacketRecord) {
        DispatchQueue.main.async {
            self.recordedPackets.append(packet)
            if self.recordedPackets.count > 150 {
                self.recordedPackets.removeFirst(self.recordedPackets.count - 150)
            }

            // If recording mode is enabled, compute live diff between the latest and previous matching packet
            if self.isRecording && self.recordedPackets.count >= 2 {
                let count = self.recordedPackets.count
                let p1 = self.recordedPackets[count - 2]
                let p2 = self.recordedPackets[count - 1]

                if p1.charUUID == p2.charUUID && p1.rawBytes.count == p2.rawBytes.count {
                    self.baselinePacket = p1
                    self.activePacket = p2
                    self.currentDiff = self.calculateDiff(baseline: p1, active: p2)
                }
            }
        }
    }

    // MARK: - Diff Computation

    public func calculateDiff(baseline: GATTPacketRecord, active: GATTPacketRecord) -> PacketDiffResult {
        var deltaIndices: [Int] = []
        let minCount = min(baseline.rawBytes.count, active.rawBytes.count)

        for i in 0..<minCount {
            if baseline.rawBytes[i] != active.rawBytes[i] {
                deltaIndices.append(i)
            }
        }

        // If lengths differ, add remaining indices
        let maxCount = max(baseline.rawBytes.count, active.rawBytes.count)
        if maxCount > minCount {
            for i in minCount..<maxCount {
                deltaIndices.append(i)
            }
        }

        var explanation = "Byte difference detected at indices: \(deltaIndices.map { String($0) }.joined(separator: ", ")). "
        if let firstDelta = deltaIndices.first, firstDelta < baseline.rawBytes.count && firstDelta < active.rawBytes.count {
            explanation += String(format: "Baseline Byte[%d] = 0x%02X, Active Byte[%d] = 0x%02X. Likely Noise Control state opcode.",
                                  firstDelta, baseline.rawBytes[firstDelta], firstDelta, active.rawBytes[firstDelta])
        }

        return PacketDiffResult(
            baseline: baseline,
            active: active,
            deltaIndices: deltaIndices,
            suggestedMode: .noiseCancellation,
            explanation: explanation
        )
    }

    private func analyzeRecordedPackets() {
        guard recordedPackets.count >= 2 else { return }

        // Find pairs of packets on the same characteristic
        for i in 0..<(recordedPackets.count - 1) {
            let p1 = recordedPackets[i]
            let p2 = recordedPackets[i + 1]

            if p1.charUUID == p2.charUUID && p1.rawBytes != p2.rawBytes {
                self.baselinePacket = p1
                self.activePacket = p2
                self.currentDiff = calculateDiff(baseline: p1, active: p2)
                break
            }
        }
    }

    // MARK: - Community Profile Exporter

    public func exportAsCommunityProfileJSON(
        vendor: ChipsetVendor = .custom,
        chipsetName: String = "Reverse-Engineered Clone",
        serviceUUID: String? = nil,
        writeUUID: String? = nil,
        notifyUUID: String? = nil,
        ancOnHex: String? = nil,
        transparencyHex: String? = nil,
        adaptiveHex: String? = nil,
        ancOffHex: String? = nil
    ) -> String {
        let baseline = baselinePacket?.payloadHex ?? "055A0400060A0001"
        let active = activePacket?.payloadHex ?? "055A0400060A0101"

        let resolvedService = serviceUUID ?? baselinePacket?.serviceUUID ?? ChipsetDatabase.KnownUUIDs.airohaPrimaryService.uuidString
        let resolvedWrite = writeUUID ?? baselinePacket?.charUUID ?? ChipsetDatabase.KnownUUIDs.airohaWriteChar.uuidString
        let resolvedNotify = notifyUUID ?? ChipsetDatabase.KnownUUIDs.airohaNotifyChar.uuidString

        let profile = ChipsetProfile(
            name: "\(chipsetName) Profile",
            vendor: vendor,
            chipset: chipsetName,
            serviceUUID: resolvedService,
            writeCharUUID: resolvedWrite,
            notifyCharUUID: resolvedNotify,
            ancOnHex: ancOnHex ?? active,
            transparencyHex: transparencyHex ?? baseline,
            adaptiveHex: adaptiveHex ?? active,
            ancOffHex: ancOffHex ?? baseline
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(profile),
           let jsonString = String(data: data, encoding: .utf8) {
            self.generatedJSONProfile = jsonString
            return jsonString
        }

        return "{}"
    }
}

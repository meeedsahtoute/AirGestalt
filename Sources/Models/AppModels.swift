//
//  AppModels.swift
//  AirGestalt
//
//  Production-ready data models for Apple Continuity, Clone Chipsets,
//  Audio DSP, and Real-Time State Management.
//

import Foundation
import SwiftUI

// MARK: - AirPods Device Models (Continuity 0x004C)

public enum AirPodsModel: Equatable, Hashable, CaseIterable, Identifiable {
    case airPods1
    case airPods2
    case airPods3
    case airPods4
    case airPodsPro
    case airPodsPro2
    case airPodsPro3
    case airPodsMax
    case unknown(UInt16)

    public var id: String { displayName }

    public static var allCases: [AirPodsModel] {
        [
            .airPodsPro2,
            .airPodsPro3,
            .airPodsPro,
            .airPods4,
            .airPods3,
            .airPods2,
            .airPods1,
            .airPodsMax
        ]
    }

    public var rawCode: UInt16 {
        switch self {
        case .airPods1: return 0x0220
        case .airPods2: return 0x0F20
        case .airPods3: return 0x1320
        case .airPods4: return 0x1920
        case .airPodsPro: return 0x0E20
        case .airPodsPro2: return 0x1420
        case .airPodsPro3: return 0x2720
        case .airPodsMax: return 0x0A20
        case .unknown(let code): return code
        }
    }

    public static func from(rawModelCode: UInt16) -> AirPodsModel {
        // Handle both standard and endian-flipped representations
        let code = rawModelCode
        let flipped = ((code & 0xFF) << 8) | ((code >> 8) & 0xFF)

        if code == 0x0220 || flipped == 0x0220 { return .airPods1 }
        if code == 0x0F20 || flipped == 0x0F20 { return .airPods2 }
        if code == 0x1320 || flipped == 0x1320 { return .airPods3 }
        if code == 0x1920 || flipped == 0x1920 { return .airPods4 }
        if code == 0x0E20 || flipped == 0x0E20 { return .airPodsPro }
        if code == 0x1420 || flipped == 0x1420 || code == 0x2420 || flipped == 0x2420 { return .airPodsPro2 }
        if code == 0x2720 || flipped == 0x2720 { return .airPodsPro3 }
        if code == 0x0A20 || flipped == 0x0A20 || code == 0x1F20 || flipped == 0x1F20 { return .airPodsMax }

        return .unknown(rawModelCode)
    }

    public var displayName: String {
        switch self {
        case .airPods1: return "AirPods (1st Gen)"
        case .airPods2: return "AirPods (2nd Gen)"
        case .airPods3: return "AirPods (3rd Gen)"
        case .airPods4: return "AirPods 4 (Active ANC)"
        case .airPodsPro: return "AirPods Pro (1st Gen)"
        case .airPodsPro2: return "AirPods Pro 2 (USB-C / Lightning)"
        case .airPodsPro3: return "AirPods Pro 3 (Gestalt Edition)"
        case .airPodsMax: return "AirPods Max (Hi-Fi ANC)"
        case .unknown(let code): return String(format: "Acoustic Clone (0x%04X)", code)
        }
    }

    public var badgeName: String {
        switch self {
        case .airPodsPro2, .airPodsPro3: return "PRO 2"
        case .airPodsPro: return "PRO"
        case .airPods4: return "GEN 4"
        case .airPods3: return "GEN 3"
        case .airPods2: return "GEN 2"
        case .airPods1: return "GEN 1"
        case .airPodsMax: return "MAX"
        case .unknown: return "CLONE"
        }
    }

    public var systemImageName: String {
        switch self {
        case .airPodsMax: return "headphones"
        case .airPodsPro, .airPodsPro2, .airPodsPro3: return "airpodspro"
        default: return "airpods"
        }
    }

    public var supportsHardwareANC: Bool {
        switch self {
        case .airPodsPro, .airPodsPro2, .airPodsPro3, .airPods4, .airPodsMax, .unknown:
            return true
        default:
            return false
        }
    }
}

// MARK: - Battery & Charging State

public struct EarbudBatteryState: Equatable, Hashable {
    public var percentage: Int? // 0...100, nil if disconnected / unavailable
    public var isCharging: Bool
    public var isConnected: Bool {
        percentage != nil
    }

    public init(percentage: Int?, isCharging: Bool) {
        self.percentage = percentage
        self.isCharging = isCharging
    }

    public static let disconnected = EarbudBatteryState(percentage: nil, isCharging: false)
}

// MARK: - Decoded Continuity Frame (0x004C Proximity)

public struct DeviceContinuityFrame: Equatable {
    public var model: AirPodsModel
    public var leftBattery: EarbudBatteryState
    public var rightBattery: EarbudBatteryState
    public var caseBattery: EarbudBatteryState
    public var leftInEar: Bool
    public var rightInEar: Bool
    public var primaryMicIsLeft: Bool
    public var lidOpenCount: UInt8
    public var rssi: Int
    public var smoothedRSSI: Double
    public var isNearProximity: Bool
    public var rawManufacturerBytes: Data
    public var timestamp: Date

    public init(
        model: AirPodsModel,
        leftBattery: EarbudBatteryState,
        rightBattery: EarbudBatteryState,
        caseBattery: EarbudBatteryState,
        leftInEar: Bool,
        rightInEar: Bool,
        primaryMicIsLeft: Bool,
        lidOpenCount: UInt8,
        rssi: Int,
        smoothedRSSI: Double,
        isNearProximity: Bool,
        rawManufacturerBytes: Data = Data(),
        timestamp: Date = Date()
    ) {
        self.model = model
        self.leftBattery = leftBattery
        self.rightBattery = rightBattery
        self.caseBattery = caseBattery
        self.leftInEar = leftInEar
        self.rightInEar = rightInEar
        self.primaryMicIsLeft = primaryMicIsLeft
        self.lidOpenCount = lidOpenCount
        self.rssi = rssi
        self.smoothedRSSI = smoothedRSSI
        self.isNearProximity = isNearProximity
        self.rawManufacturerBytes = rawManufacturerBytes
        self.timestamp = timestamp
    }
}

// MARK: - Noise Control Modes

public enum NoiseControlMode: String, CaseIterable, Identifiable, Codable {
    case off = "off"
    case transparency = "transparency"
    case adaptive = "adaptive"
    case noiseCancellation = "anc"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: return "Off"
        case .transparency: return "Transparency"
        case .adaptive: return "Adaptive"
        case .noiseCancellation: return "Max ANC"
        }
    }

    public var iconName: String {
        switch self {
        case .off: return "circle.slash"
        case .transparency: return "ear.badge.waveform"
        case .adaptive: return "waveform.badge.magnifyingglass"
        case .noiseCancellation: return "waveform.and.mic"
        }
    }

    public var activeColor: Color {
        switch self {
        case .off: return Color.gray
        case .transparency: return Color.blue
        case .adaptive: return Color.purple
        case .noiseCancellation: return Color.cyan
        }
    }
}

// MARK: - Chipset Vendors & Profiles

public enum ChipsetVendor: String, CaseIterable, Identifiable, Codable {
    case airoha = "Airoha (MediaTek)"
    case bes = "Bestechnic (BES)"
    case bluetrum = "Bluetrum (AB)"
    case huilian = "Huilian (Starlink)"
    case jl = "JieLi / Jerry (JL)"
    case qualcomm = "Qualcomm (QCC)"
    case custom = "Custom / Reverse-Engineered"

    public var id: String { rawValue }
}

public struct ChipsetProfile: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var vendor: ChipsetVendor
    public var chipset: String
    public var serviceUUID: String
    public var writeCharUUID: String
    public var notifyCharUUID: String
    public var ancOnHex: String
    public var transparencyHex: String
    public var adaptiveHex: String
    public var ancOffHex: String
    public var batteryQueryHex: String?
    public var eqBassBoostHex: String?
    public var eqTrebleBoostHex: String?
    public var eqFlatHex: String?

    public init(
        id: UUID = UUID(),
        name: String,
        vendor: ChipsetVendor,
        chipset: String,
        serviceUUID: String,
        writeCharUUID: String,
        notifyCharUUID: String,
        ancOnHex: String,
        transparencyHex: String,
        adaptiveHex: String,
        ancOffHex: String,
        batteryQueryHex: String? = nil,
        eqBassBoostHex: String? = nil,
        eqTrebleBoostHex: String? = nil,
        eqFlatHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.chipset = chipset
        self.serviceUUID = serviceUUID
        self.writeCharUUID = writeCharUUID
        self.notifyCharUUID = notifyCharUUID
        self.ancOnHex = ancOnHex
        self.transparencyHex = transparencyHex
        self.adaptiveHex = adaptiveHex
        self.ancOffHex = ancOffHex
        self.batteryQueryHex = batteryQueryHex
        self.eqBassBoostHex = eqBassBoostHex
        self.eqTrebleBoostHex = eqTrebleBoostHex
        self.eqFlatHex = eqFlatHex
    }
}

// MARK: - Packet Diffing Lab Records

public enum PacketDirection: String, Codable {
    case tx = "TX ->"
    case rx = "<- RX"
}

public struct GATTPacketRecord: Identifiable, Codable, Equatable {
    public var id: UUID
    public var timestamp: Date
    public var direction: PacketDirection
    public var serviceUUID: String
    public var charUUID: String
    public var payloadHex: String
    public var rawBytes: [UInt8]
    public var isStemToggleTriggered: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        direction: PacketDirection,
        serviceUUID: String,
        charUUID: String,
        payloadHex: String,
        rawBytes: [UInt8],
        isStemToggleTriggered: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.serviceUUID = serviceUUID
        self.charUUID = charUUID
        self.payloadHex = payloadHex
        self.rawBytes = rawBytes
        self.isStemToggleTriggered = isStemToggleTriggered
    }
}

public struct PacketDiffResult: Identifiable, Equatable {
    public var id = UUID()
    public var baseline: GATTPacketRecord
    public var active: GATTPacketRecord
    public var deltaIndices: [Int] // Indices where rawBytes differ
    public var suggestedMode: NoiseControlMode?
    public var explanation: String
}

// MARK: - Voice Studio Mic Modes

public enum VoiceMicMode: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case voiceIsolation = "Voice Isolation"
    case wideSpectrum = "Wide Spectrum"
    case studioBroadcast = "Studio Broadcast"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .standard: return "mic"
        case .voiceIsolation: return "mic.badge.plus"
        case .wideSpectrum: return "waveform.path"
        case .studioBroadcast: return "waveform.and.person.filled"
        }
    }

    public var subtitle: String {
        switch self {
        case .standard: return "Direct capture with flat response"
        case .voiceIsolation: return "Apple HW Neural Engine + adaptive gate"
        case .wideSpectrum: return "Full ambient & acoustic spectrum"
        case .studioBroadcast: return "vDSP warm EQ, 85Hz cut & compressor"
        }
    }
}

// MARK: - 10-Band Parametric EQ Presets

public struct EQPreset: Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var iconName: String
    // 10 bands: 32Hz, 64Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz (-12dB to +12dB)
    public var bandGains: [Float]

    public static let appleSignature = EQPreset(
        name: "Apple Signature",
        iconName: "applelogo",
        bandGains: [1.5, 2.5, 1.0, 0.0, -0.5, 0.5, 1.8, 2.2, 1.5, 1.0]
    )

    public static let deepBassBoost = EQPreset(
        name: "Deep Bass Boost",
        iconName: "waveform.badge.plus",
        bandGains: [6.0, 5.0, 3.5, 1.5, 0.0, 0.0, 0.0, 0.5, 1.0, 0.5]
    )

    public static let vocalClarity = EQPreset(
        name: "Vocal Clarity",
        iconName: "quote.bubble",
        bandGains: [-2.0, -1.0, 0.0, 1.0, 2.0, 3.5, 4.0, 2.5, 1.0, 0.0]
    )

    public static let studioFlat = EQPreset(
        name: "Studio Flat",
        iconName: "slider.horizontal.3",
        bandGains: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    )

    public static let allPresets: [EQPreset] = [
        .appleSignature,
        .deepBassBoost,
        .vocalClarity,
        .studioFlat
    ]
}

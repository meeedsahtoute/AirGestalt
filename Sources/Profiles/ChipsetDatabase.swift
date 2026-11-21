//
//  ChipsetDatabase.swift
//  AirGestalt
//
//  Reverse-Engineered Chipset Database for Clone & Third-Party Earbuds.
//  Includes Airoha RACE, Nordic UART / Bluetrum, BES DataPath, Huilian, and Qualcomm.
//

import Foundation
import CoreBluetooth

public struct ChipsetDatabase {
    // MARK: - Well-Known Service & Characteristic UUIDs

    public struct KnownUUIDs {
        // Airoha RACE (Remote Access Control Protocol)
        public static let airohaPrimaryService = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45") // PRIM-AirohaBLE
        public static let airohaSonyVariantService = CBUUID(string: "DC405470-A351-4A59-97D8-2E2E3B207FBB")
        public static let airohaWriteChar = CBUUID(string: "52414345-2DAB-0341-6972-6F6861424C45") // RACE-AirohaBLE
        public static let airohaNotifyChar = CBUUID(string: "4E4F5449-2DAB-0341-6972-6F6861424C45") // NOTI-AirohaBLE

        // Nordic UART / Bluetrum
        public static let nordicUARTService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
        public static let nordicUARTWriteChar = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // TX
        public static let nordicUARTNotifyChar = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // RX

        // Bestechnic (BES) DataPath / TOTA (Test Over The Air)
        public static let besDataPathService = CBUUID(string: "0000FE01-0000-1000-8000-00805F9B34FB")
        public static let besWriteChar = CBUUID(string: "0000FE02-0000-1000-8000-00805F9B34FB")
        public static let besNotifyChar = CBUUID(string: "0000FE03-0000-1000-8000-00805F9B34FB")

        // Huilian Starlink / Pro Service
        public static let huilianService = CBUUID(string: "0000FD00-0000-1000-8000-00805F9B34FB")
        public static let huilianWriteChar = CBUUID(string: "0000FD01-0000-1000-8000-00805F9B34FB")
        public static let huilianNotifyChar = CBUUID(string: "0000FD02-0000-1000-8000-00805F9B34FB")

        // Qualcomm GFPS / Custom RFCOMM GATT
        public static let qualcommService = CBUUID(string: "0000FE2C-0000-1000-8000-00805F9B34FB")
        public static let qualcommWriteChar = CBUUID(string: "0000FE2D-0000-1000-8000-00805F9B34FB")
        public static let qualcommNotifyChar = CBUUID(string: "0000FE2E-0000-1000-8000-00805F9B34FB")

        // JieLi / Jerry (JL) AC697N / JL7003 / AC8973
        public static let jlService = CBUUID(string: "0000AE00-0000-1000-8000-00805F9B34FB")
        public static let jlWriteChar = CBUUID(string: "0000AE01-0000-1000-8000-00805F9B34FB")
        public static let jlNotifyChar = CBUUID(string: "0000AE02-0000-1000-8000-00805F9B34FB")
    }

    // MARK: - Airoha RACE Protocol Constants

    public struct AirohaRACE {
        public static let syncHeader: [UInt8] = [0x05, 0x5A]

        // Safe Read-Only Diagnostic Opcodes
        public static let opcodeQuerySDKVersion: UInt16 = 0x1E08
        public static let opcodeQueryClassicBDAddr: UInt16 = 0x0CD5
        public static let opcodeQueryBattery: UInt16 = 0x0A02
        public static let opcodeQueryANCSettings: UInt16 = 0x0A06

        // Destructive Opcodes (Strictly Blocked by Safety Lock)
        public static let opcodeFlashWrite: UInt16 = 0x1681
        public static let opcodeFOTAStart: UInt16 = 0x1600
        public static let opcodeNVRAMWrite: UInt16 = 0x1682
        public static let opcodeSectorErase: UInt16 = 0x1683

        public static let dangerousOpcodes: Set<UInt16> = [
            opcodeFlashWrite,
            opcodeFOTAStart,
            opcodeNVRAMWrite,
            opcodeSectorErase
        ]
    }

    // MARK: - Pre-Engineered Community Profiles

    public static let communityProfiles: [ChipsetProfile] = [
        // 1. Airoha AB1562A / AB1562E / AB1562F
        ChipsetProfile(
            name: "Airoha AB1562A / E / F (Standard RACE)",
            vendor: .airoha,
            chipset: "AB1562A/E/F",
            serviceUUID: KnownUUIDs.airohaPrimaryService.uuidString,
            writeCharUUID: KnownUUIDs.airohaWriteChar.uuidString,
            notifyCharUUID: KnownUUIDs.airohaNotifyChar.uuidString,
            ancOnHex: "055A0400060A0101",        // Opcode 0x0A06, Param 0x01 (Max ANC)
            transparencyHex: "055A0400060A0201", // Opcode 0x0A06, Param 0x02 (Transparency)
            adaptiveHex: "055A0400060A0401",     // Opcode 0x0A06, Param 0x04 (Adaptive)
            ancOffHex: "055A0400060A0001",       // Opcode 0x0A06, Param 0x00 (ANC Off)
            batteryQueryHex: "055A0200020A",
            eqBassBoostHex: "055A0500100B010100",
            eqTrebleBoostHex: "055A0500100B020100",
            eqFlatHex: "055A0500100B000100"
        ),

        // 2. Airoha AB1565 Flagship Hybrid ANC
        ChipsetProfile(
            name: "Airoha AB1565 (Next-Gen Flagship)",
            vendor: .airoha,
            chipset: "AB1565",
            serviceUUID: KnownUUIDs.airohaSonyVariantService.uuidString,
            writeCharUUID: KnownUUIDs.airohaWriteChar.uuidString,
            notifyCharUUID: KnownUUIDs.airohaNotifyChar.uuidString,
            ancOnHex: "055A0400060A0103",
            transparencyHex: "055A0400060A0203",
            adaptiveHex: "055A0400060A0503",
            ancOffHex: "055A0400060A0003",
            batteryQueryHex: "055A0200020A",
            eqBassBoostHex: "055A0500100B030100",
            eqTrebleBoostHex: "055A0500100B040100",
            eqFlatHex: "055A0500100B000100"
        ),

        // 3. Bluetrum BT8892 / BT8922 (Nordic UART Framing)
        ChipsetProfile(
            name: "Bluetrum BT8892 / BT8922 (NUS Framing)",
            vendor: .bluetrum,
            chipset: "BT8892 / BT8922",
            serviceUUID: KnownUUIDs.nordicUARTService.uuidString,
            writeCharUUID: KnownUUIDs.nordicUARTWriteChar.uuidString,
            notifyCharUUID: KnownUUIDs.nordicUARTNotifyChar.uuidString,
            ancOnHex: "AA5503010100FF",
            transparencyHex: "AA5503010200FE",
            adaptiveHex: "AA5503010300FD",
            ancOffHex: "AA550301000000",
            batteryQueryHex: "AA55020200FB",
            eqBassBoostHex: "AA5503050100FA",
            eqTrebleBoostHex: "AA5503050200F9",
            eqFlatHex: "AA5503050000FB"
        ),

        // 4. Bestechnic BES2300 / BES2500 / BES2600 (TOTA)
        ChipsetProfile(
            name: "Bestechnic BES2500 / BES2600 (TOTA DataPath)",
            vendor: .bes,
            chipset: "BES2500/2600",
            serviceUUID: KnownUUIDs.besDataPathService.uuidString,
            writeCharUUID: KnownUUIDs.besWriteChar.uuidString,
            notifyCharUUID: KnownUUIDs.besNotifyChar.uuidString,
            ancOnHex: "BE550401010000DF",
            transparencyHex: "BE550401020000DE",
            adaptiveHex: "BE550401030000DD",
            ancOffHex: "BE550401000000E0",
            batteryQueryHex: "BE55020400FA",
            eqBassBoostHex: "BE5503070100F1",
            eqTrebleBoostHex: "BE5503070200F0",
            eqFlatHex: "BE5503070000F2"
        ),

        // 5. Huilian Starlink H2S Pro / A6 Pro
        ChipsetProfile(
            name: "Huilian H2S Pro / A6 Pro",
            vendor: .huilian,
            chipset: "H2S Pro",
            serviceUUID: KnownUUIDs.huilianService.uuidString,
            writeCharUUID: KnownUUIDs.huilianWriteChar.uuidString,
            notifyCharUUID: KnownUUIDs.huilianNotifyChar.uuidString,
            ancOnHex: "7E040101007E",
            transparencyHex: "7E040102007E",
            adaptiveHex: "7E040103007E",
            ancOffHex: "7E040100007E",
            batteryQueryHex: "7E0205007E",
            eqBassBoostHex: "7E0308017E",
            eqTrebleBoostHex: "7E0308027E",
            eqFlatHex: "7E0308007E"
        ),

        // 6. Qualcomm QCC3040 / QCC5141
        ChipsetProfile(
            name: "Qualcomm QCC3040 / QCC5141",
            vendor: .qualcomm,
            chipset: "QCC3040/5141",
            serviceUUID: KnownUUIDs.qualcommService.uuidString,
            writeCharUUID: KnownUUIDs.qualcommWriteChar.uuidString,
            notifyCharUUID: KnownUUIDs.qualcommNotifyChar.uuidString,
            ancOnHex: "000401010002",
            transparencyHex: "000401020003",
            adaptiveHex: "000401030004",
            ancOffHex: "000401000001",
            batteryQueryHex: "00020300",
            eqBassBoostHex: "00030501",
            eqTrebleBoostHex: "00030502",
            eqFlatHex: "00030500"
        ),

        // 7. JieLi / Jerry (JL7003 / AC8973)
        ChipsetProfile(
            name: "JieLi / Jerry (JL7003 / AC8973)",
            vendor: .jl,
            chipset: "JL7003/AC8973",
            serviceUUID: KnownUUIDs.jlService.uuidString,
            writeCharUUID: KnownUUIDs.jlWriteChar.uuidString,
            notifyCharUUID: KnownUUIDs.jlNotifyChar.uuidString,
            ancOnHex: "FA5503010100",
            transparencyHex: "FA5503010200",
            adaptiveHex: "FA5503010300",
            ancOffHex: "FA5503010000",
            batteryQueryHex: "FA55020100",
            eqBassBoostHex: "FA5503040100",
            eqTrebleBoostHex: "FA5503040200",
            eqFlatHex: "FA5503040000"
        )
    ]

    // MARK: - Profile Matching Helpers

    public static func profileForServiceUUID(_ uuidString: String) -> ChipsetProfile? {
        let clean = uuidString.uppercased()
        return communityProfiles.first { profile in
            profile.serviceUUID.uppercased() == clean ||
            clean.contains(profile.serviceUUID.uppercased())
        }
    }

    public static func defaultProfile() -> ChipsetProfile {
        return communityProfiles[0] // Airoha AB1562
    }
}

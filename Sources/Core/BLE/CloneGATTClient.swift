//
//  CloneGATTClient.swift
//  AirGestalt
//
//  Dedicated Hardware Clone ANC Unlocker & BLE GATT Client.
//  Connects to Airoha RACE, Nordic UART / Bluetrum, and BES DataPath,
//  with 6-byte RACE framing, read-only diagnostic probing, and a HARD safety lock.
//

import Foundation
import CoreBluetooth
import Combine

public enum ChipsetSafetyError: LocalizedError {
    case destructiveOpcodeBlocked(opcode: UInt16)
    case writeCharacteristicNotFound
    case invalidHexPayload(hex: String)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .destructiveOpcodeBlocked(let opcode):
            return String(format: "CRITICAL SAFETY LOCK: Destructive Opcode 0x%04X blocked! Flash/FOTA writing is prohibited to protect clone hardware from permanent bricking.", opcode)
        case .writeCharacteristicNotFound:
            return "GATT Error: No writable characteristic discovered on the connected clone earbud."
        case .invalidHexPayload(let hex):
            return "GATT Error: Malformed hex command string: '\(hex)'"
        case .notConnected:
            return "GATT Error: Not connected to an earbud GATT peripheral."
        }
    }
}

public final class CloneGATTClient: NSObject, ObservableObject {
    public static let shared = CloneGATTClient()

    // MARK: - Published State
    @Published public var isConnected: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var isProbing: Bool = false
    @Published public var connectedPeripheralName: String? = nil
    @Published public var activeProfile: ChipsetProfile? = ChipsetDatabase.defaultProfile()
    @Published public var detectedChipsetName: String? = nil
    @Published public var socModelInfo: String? = nil
    @Published public var classicBDAddress: String? = nil
    @Published public var isBrickingSafetyLockEngaged: Bool = true
    @Published public var lastSentHex: String? = nil
    @Published public var lastReceivedHex: String? = nil
    @Published public var currentNoiseMode: NoiseControlMode = .off

    // MARK: - CoreBluetooth State
    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var activeWriteCharacteristic: CBCharacteristic?
    private var activeNotifyCharacteristic: CBCharacteristic?

    // Forwarding closure for Packet Diffing Lab
    public var onPacketCaptured: ((GATTPacketRecord) -> Void)?

    public override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    // MARK: - Connection Management

    public func connect(to peripheral: CBPeripheral) {
        self.targetPeripheral = peripheral
        self.targetPeripheral?.delegate = self
        self.isConnecting = true
        centralManager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    public func disconnect() {
        if let p = targetPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        isConnected = false
        isConnecting = false
        targetPeripheral = nil
        activeWriteCharacteristic = nil
        activeNotifyCharacteristic = nil
    }

    // MARK: - Auto-Detect Hardware ANC Probe

    public func autoDetectHardwareANC() {
        guard isConnected, let peripheral = targetPeripheral else { return }

        isProbing = true

        // 1. Probe for Airoha RACE diagnostic opcode 0x1E08 (SDK / SoC query)
        do {
            let raceProbe = try buildRACEFrame(opcode: ChipsetDatabase.AirohaRACE.opcodeQuerySDKVersion, payload: Data())
            sendRawBytes(raceProbe, direction: .tx)
        } catch {
            print("AutoDetect: Airoha probe error: \(error)")
        }

        // 2. Discover matching services against ChipsetDatabase
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            self.matchDiscoveredServicesWithProfile()
            self.isProbing = false
        }
    }

    private func matchDiscoveredServicesWithProfile() {
        guard let services = targetPeripheral?.services else { return }

        for service in services {
            let serviceUUID = service.uuid.uuidString
            if let matched = ChipsetDatabase.profileForServiceUUID(serviceUUID) {
                self.activeProfile = matched
                self.detectedChipsetName = "\(matched.vendor.rawValue) - \(matched.chipset)"
                return
            }
        }

        // If no direct service match, check characteristic UUIDs
        if activeWriteCharacteristic?.uuid == ChipsetDatabase.KnownUUIDs.airohaWriteChar {
            self.activeProfile = ChipsetDatabase.communityProfiles[0]
            self.detectedChipsetName = "Airoha AB1562 (RACE)"
        } else if activeWriteCharacteristic?.uuid == ChipsetDatabase.KnownUUIDs.nordicUARTWriteChar {
            self.activeProfile = ChipsetDatabase.communityProfiles[2]
            self.detectedChipsetName = "Bluetrum / Nordic UART"
        } else if activeWriteCharacteristic?.uuid == ChipsetDatabase.KnownUUIDs.besWriteChar {
            self.activeProfile = ChipsetDatabase.communityProfiles[3]
            self.detectedChipsetName = "Bestechnic BES TOTA"
        }
    }

    // MARK: - Safe RACE Packet Framing (6-Byte Header)

    public func buildRACEFrame(opcode: UInt16, payload: Data) throws -> Data {
        // HARD SAFETY LOCK: Check if opcode is dangerous
        if isBrickingSafetyLockEngaged && ChipsetDatabase.AirohaRACE.dangerousOpcodes.contains(opcode) {
            throw ChipsetSafetyError.destructiveOpcodeBlocked(opcode: opcode)
        }

        // RACE Framing:
        // [0..1]: Sync (0x05, 0x5A)
        // [2..3]: Payload length (UInt16 LE = opcode size (2) + payload.count)
        // [4..5]: Opcode (UInt16 LE)
        // [6...]: Payload bytes
        var packet = Data(ChipsetDatabase.AirohaRACE.syncHeader)
        let totalPayloadLen = UInt16(2 + payload.count)

        // Little Endian Length
        packet.append(UInt8(totalPayloadLen & 0xFF))
        packet.append(UInt8((totalPayloadLen >> 8) & 0xFF))

        // Little Endian Opcode
        packet.append(UInt8(opcode & 0xFF))
        packet.append(UInt8((opcode >> 8) & 0xFF))

        // Append Payload
        packet.append(payload)
        return packet
    }

    // MARK: - ANC Command Dispatcher

    public func sendNoiseMode(_ mode: NoiseControlMode) {
        guard let profile = activeProfile else { return }

        let hexCommand: String
        switch mode {
        case .noiseCancellation:
            hexCommand = profile.ancOnHex
        case .transparency:
            hexCommand = profile.transparencyHex
        case .adaptive:
            hexCommand = profile.adaptiveHex
        case .off:
            hexCommand = profile.ancOffHex
        }

        guard let data = Data(hexString: hexCommand) else {
            print("Failed to convert hex command to data: \(hexCommand)")
            return
        }

        sendRawBytes(data, direction: .tx)
        DispatchQueue.main.async {
            self.currentNoiseMode = mode
            self.lastSentHex = hexCommand
        }
    }

    public func sendHardwareEQPreset(_ preset: EQPreset) {
        guard let profile = activeProfile else { return }

        let hex: String?
        switch preset.name {
        case "Deep Bass Boost":
            hex = profile.eqBassBoostHex
        case "Vocal Clarity":
            hex = profile.eqTrebleBoostHex
        default:
            hex = profile.eqFlatHex
        }

        guard let targetHex = hex, let data = Data(hexString: targetHex) else { return }
        sendRawBytes(data, direction: .tx)
        DispatchQueue.main.async {
            self.lastSentHex = targetHex
        }
    }

    // MARK: - Low-Level GATT Transmission

    public func sendRawBytes(_ data: Data, direction: PacketDirection = .tx) {
        guard let peripheral = targetPeripheral,
              let writeChar = activeWriteCharacteristic else {
            print("Cannot send bytes: peripheral or write char unavailable.")
            return
        }

        let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: writeChar, type: writeType)

        let hex = data.map { String(format: "%02X", $0) }.joined()
        self.lastSentHex = hex

        let record = GATTPacketRecord(
            timestamp: Date(),
            direction: direction,
            serviceUUID: writeChar.service?.uuid.uuidString ?? "Unknown",
            charUUID: writeChar.uuid.uuidString,
            payloadHex: hex,
            rawBytes: [UInt8](data)
        )
        onPacketCaptured?(record)
    }

    public func sendCustomHex(_ hexString: String) throws {
        guard let data = Data(hexString: hexString) else {
            throw ChipsetSafetyError.invalidHexPayload(hex: hexString)
        }

        // Inspect if this looks like a RACE frame with a dangerous opcode
        if data.count >= 6 && data[0] == 0x05 && data[1] == 0x5A {
            let opcode = UInt16(data[4]) | (UInt16(data[5]) << 8)
            if isBrickingSafetyLockEngaged && ChipsetDatabase.AirohaRACE.dangerousOpcodes.contains(opcode) {
                throw ChipsetSafetyError.destructiveOpcodeBlocked(opcode: opcode)
            }
        }

        sendRawBytes(data, direction: .tx)
    }
}

// MARK: - CBCentralManagerDelegate

extension CloneGATTClient: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // State updates
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        isConnecting = false
        connectedPeripheralName = peripheral.name ?? "AirPods Pro (Clone)"

        // Discover all services
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        isConnecting = false
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        isConnecting = false
        connectedPeripheralName = nil
        targetPeripheral = nil
        activeWriteCharacteristic = nil
        activeNotifyCharacteristic = nil
    }
}

// MARK: - CBPeripheralDelegate

extension CloneGATTClient: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for char in characteristics {
            // Find writable characteristic
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                if activeWriteCharacteristic == nil ||
                   char.uuid == ChipsetDatabase.KnownUUIDs.airohaWriteChar ||
                   char.uuid == ChipsetDatabase.KnownUUIDs.nordicUARTWriteChar ||
                   char.uuid == ChipsetDatabase.KnownUUIDs.besWriteChar {
                    activeWriteCharacteristic = char
                }
            }

            // Find notifying characteristic
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: char)
                if activeNotifyCharacteristic == nil {
                    activeNotifyCharacteristic = char
                }
            }
        }

        matchDiscoveredServicesWithProfile()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }

        let hex = data.map { String(format: "%02X", $0) }.joined()
        DispatchQueue.main.async {
            self.lastReceivedHex = hex
        }

        let record = GATTPacketRecord(
            timestamp: Date(),
            direction: .rx,
            serviceUUID: characteristic.service?.uuid.uuidString ?? "Unknown",
            charUUID: characteristic.uuid.uuidString,
            payloadHex: hex,
            rawBytes: [UInt8](data)
        )
        onPacketCaptured?(record)

        // Parse RACE Diagnostic responses
        if data.count >= 6 && data[0] == 0x05 && data[1] == 0x5A {
            let opcode = UInt16(data[4]) | (UInt16(data[5]) << 8)

            if opcode == ChipsetDatabase.AirohaRACE.opcodeQuerySDKVersion {
                let sdkPayload = data.dropFirst(6)
                if let str = String(data: sdkPayload, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.socModelInfo = "Airoha SoC (\(str.trimmingCharacters(in: .whitespacesAndNewlines)))"
                    }
                } else {
                    let hexSDK = sdkPayload.map { String(format: "%02X", $0) }.joined()
                    DispatchQueue.main.async {
                        self.socModelInfo = "Airoha SoC (Raw: \(hexSDK))"
                    }
                }
            } else if opcode == ChipsetDatabase.AirohaRACE.opcodeQueryClassicBDAddr {
                let addrBytes = [UInt8](data.dropFirst(6).prefix(6))
                let mac = addrBytes.reversed().map { String(format: "%02X", $0) }.joined(separator: ":")
                DispatchQueue.main.async {
                    self.classicBDAddress = mac
                }
            }
        }
    }
}

// MARK: - Data Hex Extension Helper

extension Data {
    public init?(hexString: String) {
        let clean = hexString.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard clean.count % 2 == 0 else { return nil }

        var data = Data()
        var index = clean.startIndex

        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            let byteStr = clean[index..<nextIndex]
            guard let byte = UInt8(byteStr, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}

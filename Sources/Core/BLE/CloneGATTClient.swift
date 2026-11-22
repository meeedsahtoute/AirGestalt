//
//  CloneGATTClient.swift
//  AirGestalt
//
//  Dedicated Hardware Clone ANC Unlocker & BLE GATT Client.
//  Connects to Airoha RACE, Nordic UART / Bluetrum, BES DataPath, and JieLi (JL),
//  with 6-byte RACE framing, read-only diagnostic probing, interactive auto-detection,
//  smart TV/clutter filtering, RSSI-descending sorting, persistent auto-reconnect,
//  real battery polling, and a persistent anti-bricking safety lock.
//

import Foundation
import CoreBluetooth
import Combine

public struct DiscoveredCloneDevice: Identifiable, Equatable {
    public var id: UUID { peripheral.identifier }
    public let peripheral: CBPeripheral
    public let name: String
    public let rssi: Int
    public let advertisedServices: [String]
    public let probableVendor: ChipsetVendor?
}

public enum GATTConnectionState: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected ✓"
    case failed = "Connection Failed"
}

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

    // MARK: - Clutter Keywords for TV & Appliance Filtering
    public static let clutterKeywords = [
        "tv", "samsung", "crystal", "lg", "bravia", "roku", "firetv",
        "smart tv", "soundbar", "chromecast", "panasonic", "hisense",
        "tcl", "vizio", "philips", "refrigerator", "microwave", "printer"
    ]

    // MARK: - Published State
    @Published public var connectionState: GATTConnectionState = .disconnected
    @Published public var isConnected: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var isProbing: Bool = false
    @Published public var isDetectingChipset: Bool = false
    @Published public var detectionStatusMessage: String = "Tap to Auto-Detect Chipset"
    @Published public var lastGATTStatus: String = "Ready"
    @Published public var showDetectionSheet: Bool = false
    @Published public var showAllDevices: Bool = UserDefaults.standard.bool(forKey: "com.airgestalt.showAllDevices") {
        didSet {
            UserDefaults.standard.set(showAllDevices, forKey: "com.airgestalt.showAllDevices")
        }
    }
    @Published public var discoveredCloneDevices: [DiscoveredCloneDevice] = []

    @Published public var connectedPeripheralName: String? = nil
    @Published public var activeProfile: ChipsetProfile? = ChipsetDatabase.defaultProfile()
    @Published public var detectedChipsetName: String? = nil
    @Published public var socModelInfo: String? = nil
    @Published public var classicBDAddress: String? = nil
    @Published public var isBrickingSafetyLockEngaged: Bool = (UserDefaults.standard.object(forKey: "com.airgestalt.safetyLockEnabled") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(isBrickingSafetyLockEngaged, forKey: "com.airgestalt.safetyLockEnabled")
        }
    }
    @Published public var lastSentHex: String? = nil
    @Published public var lastReceivedHex: String? = nil
    @Published public var currentNoiseMode: NoiseControlMode = .off

    // Polled Real GATT Battery Levels
    @Published public var gattLeftBattery: Int? = nil
    @Published public var gattRightBattery: Int? = nil
    @Published public var gattCaseBattery: Int? = nil

    // MARK: - CoreBluetooth State
    private var centralManager: CBCentralManager?
    private var targetPeripheral: CBPeripheral?
    private var activeWriteCharacteristic: CBCharacteristic?
    private var activeNotifyCharacteristic: CBCharacteristic?
    private var scanTimeoutTimer: Timer?
    private var batteryPollingTimer: Timer?

    // Forwarding closure for Packet Diffing Lab
    public var onPacketCaptured: ((GATTPacketRecord) -> Void)?

    public override init() {
        super.init()
        let options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        self.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main, options: options)
    }

    // MARK: - Connection Management

    public func connect(to peripheral: CBPeripheral) {
        stopScan()
        self.targetPeripheral = peripheral
        self.targetPeripheral?.delegate = self
        self.isConnecting = true
        self.connectionState = .connecting
        let name = peripheral.name ?? "Earbud"
        self.detectionStatusMessage = "Connecting to \(name)..."
        self.lastGATTStatus = "Connecting to \(name)..."

        // Persist last connected peripheral UUID for auto-reconnection
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "com.airgestalt.lastConnectedPeripheralUUID")

        centralManager?.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    public func disconnect() {
        if let p = targetPeripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
        batteryPollingTimer?.invalidate()
        batteryPollingTimer = nil
        isConnected = false
        isConnecting = false
        isProbing = false
        connectionState = .disconnected
        targetPeripheral = nil
        activeWriteCharacteristic = nil
        activeNotifyCharacteristic = nil
        detectionStatusMessage = "Disconnected"
        lastGATTStatus = "Disconnected"
    }

    private func autoReconnectLastPeripheral() {
        guard let savedUUIDString = UserDefaults.standard.string(forKey: "com.airgestalt.lastConnectedPeripheralUUID"),
              let savedUUID = UUID(uuidString: savedUUIDString),
              let central = centralManager, central.state == .poweredOn else { return }

        let peripherals = central.retrievePeripherals(withIdentifiers: [savedUUID])
        if let lastPeripheral = peripherals.first, targetPeripheral == nil {
            print("Auto-reconnecting to paired earbud: \(lastPeripheral.name ?? savedUUIDString)")
            connect(to: lastPeripheral)
        }
    }

    // MARK: - Interactive Auto-Detect ANC Probing & Scanning

    public func startAutoDetectANCScan() {
        showDetectionSheet = true
        discoveredCloneDevices.removeAll()

        if isConnected {
            // Already connected to GATT, run diagnostic probe directly
            autoDetectHardwareANC()
            return
        }

        guard let central = centralManager, central.state == .poweredOn else {
            detectionStatusMessage = "Bluetooth is currently unavailable."
            lastGATTStatus = "Bluetooth unavailable."
            return
        }

        isDetectingChipset = true
        detectionStatusMessage = "Scanning BLE frequencies for clone earbuds..."
        lastGATTStatus = "Scanning for clone peripherals..."

        // Scan for all peripherals
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.stopScan()
            if self.discoveredCloneDevices.isEmpty {
                self.detectionStatusMessage = "No clone earbuds discovered. Ensure earbuds are out of the case."
                self.lastGATTStatus = "Scan completed: 0 devices found."
            } else {
                self.detectionStatusMessage = "Discovered \(self.discoveredCloneDevices.count) device(s). Select one to connect."
                self.lastGATTStatus = "Scan completed: \(self.discoveredCloneDevices.count) device(s) found."
            }
        }
    }

    public func stopScan() {
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        centralManager?.stopScan()
        isDetectingChipset = false
    }

    public func autoDetectHardwareANC() {
        guard isConnected, let _ = targetPeripheral else {
            startAutoDetectANCScan()
            return
        }

        isProbing = true
        detectionStatusMessage = "Fingerprinting chipset GATT profiles..."
        lastGATTStatus = "Probing chipset diagnostic opcodes..."

        // 1. Probe for Airoha RACE diagnostic opcode 0x1E08 (SDK / SoC query)
        do {
            let raceProbe = try buildRACEFrame(opcode: ChipsetDatabase.AirohaRACE.opcodeQuerySDKVersion, payload: Data())
            sendRawBytes(raceProbe, direction: .tx)
        } catch {
            print("AutoDetect: Airoha probe error: \(error)")
        }

        // 2. Query Battery via RACE opcode 0x0A02
        queryBatteryViaRACE()

        // 3. Discover matching services against ChipsetDatabase
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            self.matchDiscoveredServicesWithProfile()
            self.isProbing = false
            self.detectionStatusMessage = "Identified: \(self.detectedChipsetName ?? "Standard Clone Profile")"
            self.lastGATTStatus = "Profile active: \(self.detectedChipsetName ?? "Standard")"
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
        } else if activeWriteCharacteristic?.uuid == ChipsetDatabase.KnownUUIDs.jlWriteChar {
            self.activeProfile = ChipsetDatabase.communityProfiles.first(where: { $0.vendor == .jl })
            self.detectedChipsetName = "JieLi / Jerry (JL)"
        } else {
            self.detectedChipsetName = "Acoustic Clone (Generic Profile)"
        }
    }

    // MARK: - Safe RACE Packet Framing (6-Byte Header)

    public func buildRACEFrame(opcode: UInt16, payload: Data) throws -> Data {
        // HARD SAFETY LOCK: Block dangerous opcodes to protect flash/NVRAM from bricking
        if isBrickingSafetyLockEngaged && ChipsetDatabase.AirohaRACE.dangerousOpcodes.contains(opcode) {
            throw ChipsetSafetyError.destructiveOpcodeBlocked(opcode: opcode)
        }

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

    // MARK: - Real Hardware BLE ANC Command Dispatcher

    public func sendNoiseMode(_ mode: NoiseControlMode) {
        let profile = activeProfile ?? ChipsetDatabase.defaultProfile()

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
            self.lastGATTStatus = "Invalid hex command for profile: \(hexCommand)"
            return
        }

        guard isConnected, activeWriteCharacteristic != nil else {
            self.currentNoiseMode = mode
            self.lastGATTStatus = "BLE Offline: \(mode.title) (Connect earbud in GATT Lab)"
            return
        }

        sendRawBytes(data, direction: .tx)
        DispatchQueue.main.async {
            self.currentNoiseMode = mode
            self.lastSentHex = hexCommand
            self.lastGATTStatus = "TX Sent (\(mode.title)): \(hexCommand)"
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
            self.lastGATTStatus = "TX Sent (EQ): \(targetHex)"
        }
    }

    public func queryBatteryViaRACE() {
        guard isConnected else { return }
        do {
            let battQuery = try buildRACEFrame(opcode: ChipsetDatabase.AirohaRACE.opcodeQueryBattery, payload: Data())
            sendRawBytes(battQuery, direction: .tx)
        } catch {
            print("Battery query error: \(error)")
        }
    }

    // MARK: - Low-Level GATT Transmission

    public func sendRawBytes(_ data: Data, direction: PacketDirection = .tx) {
        guard let peripheral = targetPeripheral,
              let writeChar = activeWriteCharacteristic else {
            self.lastGATTStatus = "TX Error: No writable characteristic connected."
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

        guard isConnected, activeWriteCharacteristic != nil else {
            throw ChipsetSafetyError.notConnected
        }

        sendRawBytes(data, direction: .tx)
        self.lastGATTStatus = "Custom TX Sent: \(hexString)"
    }
}

// MARK: - CBCentralManagerDelegate

extension CloneGATTClient: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            autoReconnectLastPeripheral()
        } else {
            isDetectingChipset = false
            isConnected = false
            connectionState = .disconnected
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Bluetooth Audio Accessory"
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString } ?? []

        // Smart Clutter & TV Filtering
        if !self.showAllDevices {
            let lowerName = name.lowercased()
            let isClutter = CloneGATTClient.clutterKeywords.contains(where: { lowerName.contains($0) })
            if isClutter { return }

            // Filter unnamed weak noise signals (< -85 dBm)
            if (name == "Bluetooth Audio Accessory" || name.isEmpty) && RSSI.intValue < -85 && serviceUUIDs.isEmpty {
                return
            }
        }

        var vendor: ChipsetVendor? = nil
        for s in serviceUUIDs {
            if let matched = ChipsetDatabase.profileForServiceUUID(s) {
                vendor = matched.vendor
                break
            }
        }

        let device = DiscoveredCloneDevice(
            peripheral: peripheral,
            name: name,
            rssi: RSSI.intValue,
            advertisedServices: serviceUUIDs,
            probableVendor: vendor
        )

        DispatchQueue.main.async {
            if let index = self.discoveredCloneDevices.firstIndex(where: { $0.id == device.id }) {
                self.discoveredCloneDevices[index] = device
            } else {
                self.discoveredCloneDevices.append(device)
            }
            // Sort dynamically by strongest signal (RSSI descending)
            self.discoveredCloneDevices.sort { $0.rssi > $1.rssi }
        }

        // Auto-reconnect if matching last paired device
        if let savedUUID = UserDefaults.standard.string(forKey: "com.airgestalt.lastConnectedPeripheralUUID"),
           peripheral.identifier.uuidString == savedUUID,
           targetPeripheral == nil {
            connect(to: peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        isConnecting = false
        connectionState = .connected
        connectedPeripheralName = peripheral.name ?? "AirPods Pro (Clone)"
        let name = connectedPeripheralName ?? "Earbud"
        detectionStatusMessage = "Connected to \(name). Discovering services..."
        lastGATTStatus = "Connected to \(name) ✓"

        // Discover all services
        peripheral.discoverServices(nil)

        // Setup periodic battery polling timer every 30 seconds
        batteryPollingTimer?.invalidate()
        batteryPollingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.queryBatteryViaRACE()
        }
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        isConnecting = false
        connectionState = .failed
        detectionStatusMessage = "Connection failed: \(error?.localizedDescription ?? "Unknown")"
        lastGATTStatus = "Failed: \(error?.localizedDescription ?? "Unknown")"
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        isConnecting = false
        connectionState = .disconnected
        connectedPeripheralName = nil
        targetPeripheral = nil
        activeWriteCharacteristic = nil
        activeNotifyCharacteristic = nil
        batteryPollingTimer?.invalidate()
        batteryPollingTimer = nil
        detectionStatusMessage = "Disconnected from earbud"
        lastGATTStatus = "Disconnected"
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
            // Writable characteristic discovery
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                if activeWriteCharacteristic == nil ||
                   char.uuid == ChipsetDatabase.KnownUUIDs.airohaWriteChar ||
                   char.uuid == ChipsetDatabase.KnownUUIDs.nordicUARTWriteChar ||
                   char.uuid == ChipsetDatabase.KnownUUIDs.besWriteChar ||
                   char.uuid == ChipsetDatabase.KnownUUIDs.jlWriteChar {
                    activeWriteCharacteristic = char
                }
            }

            // Notification characteristic discovery
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: char)
                if activeNotifyCharacteristic == nil {
                    activeNotifyCharacteristic = char
                }
            }

            // Standard Battery Level Characteristic (0x2A19)
            if char.uuid == ContinuityDecoder.batteryLevelCharUUID {
                peripheral.readValue(for: char)
                peripheral.setNotifyValue(true, for: char)
            }
        }

        matchDiscoveredServicesWithProfile()

        // If newly connected and writable char found, auto-probe diagnostic info and battery
        if activeWriteCharacteristic != nil && !isProbing {
            autoDetectHardwareANC()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }

        // Standard BLE Battery Level read (0x2A19)
        if characteristic.uuid == ContinuityDecoder.batteryLevelCharUUID {
            let batteryVal = Int(data[0])
            DispatchQueue.main.async {
                self.gattLeftBattery = batteryVal
                self.gattRightBattery = batteryVal
            }
        }

        let hex = data.map { String(format: "%02X", $0) }.joined()
        DispatchQueue.main.async {
            self.lastReceivedHex = hex
            self.lastGATTStatus = "RX ACK: \(hex)"
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

        // Parse RACE Diagnostic responses (Sync: 0x05, 0x5A)
        if data.count >= 6 && data[0] == 0x05 && data[1] == 0x5A {
            let opcode = UInt16(data[4]) | (UInt16(data[5]) << 8)

            if opcode == ChipsetDatabase.AirohaRACE.opcodeQuerySDKVersion {
                let sdkPayload = data.dropFirst(6)
                if let str = String(data: sdkPayload, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.socModelInfo = "Airoha SoC (\(str.trimmingCharacters(in: .whitespacesAndNewlines)))"
                    }
                }
            } else if opcode == ChipsetDatabase.AirohaRACE.opcodeQueryClassicBDAddr {
                let addrBytes = [UInt8](data.dropFirst(6).prefix(6))
                let mac = addrBytes.reversed().map { String(format: "%02X", $0) }.joined(separator: ":")
                DispatchQueue.main.async {
                    self.classicBDAddress = mac
                }
            } else if opcode == ChipsetDatabase.AirohaRACE.opcodeQueryBattery {
                // RACE Battery Payload layout: [LeftByte, RightByte, CaseByte]
                let payload = [UInt8](data.dropFirst(6))
                if payload.count >= 2 {
                    let left = Int(payload[0])
                    let right = Int(payload[1])
                    let caseVal = payload.count >= 3 ? Int(payload[2]) : nil
                    DispatchQueue.main.async {
                        self.gattLeftBattery = (left <= 100) ? left : nil
                        self.gattRightBattery = (right <= 100) ? right : nil
                        if let c = caseVal, c <= 100 {
                            self.gattCaseBattery = c
                        }
                    }
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

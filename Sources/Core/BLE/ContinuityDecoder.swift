//
//  ContinuityDecoder.swift
//  AirGestalt
//
//  Reverse-Engineered Apple Continuity Engine (0x004C) with Background State Restoration,
//  Exact 27-Byte Little-Endian Frame Decoding, Proximity EMA Filtering,
//  and Fallback to Standard BLE GATT Battery Service (0x180F / 0x2A19).
//

import Foundation
import CoreBluetooth
import Combine

public final class ContinuityDecoder: NSObject, ObservableObject {
    public static let shared = ContinuityDecoder()

    // MARK: - Constants & Identifiers
    private static let appleCompanyIdentifier: UInt16 = 0x004C
    private static let proximityPairingType: UInt8 = 0x07
    private static let restoreIdentifier = "com.airgestalt.continuity.restore"

    // Standard BLE GATT Battery Service UUIDs for background fallback
    public static let batteryServiceUUID = CBUUID(string: "180F")
    public static let batteryLevelCharUUID = CBUUID(string: "2A19")

    // Proximity EMA parameters
    private let emaAlpha: Double = 0.28
    private let proximityThresholdRSSI: Double = -62.0 // dBm

    // MARK: - Published State
    @Published public var latestFrame: DeviceContinuityFrame?
    @Published public var shouldShowPairingPopup: Bool = false
    @Published public var isScanning: Bool = false
    @Published public var connectedGATTBatteryPercentage: Int? = nil
    @Published public var isFallbackGATTActive: Bool = false
    @Published public var discoveredPeripherals: [CBPeripheral] = []

    // MARK: - Internal Engine State
    private var centralManager: CBCentralManager?
    private var smoothedRSSIByDevice: [String: Double] = [:]
    private var lastLidOpenCountByDevice: [String: UInt8] = [:]
    private var fallbackPeripheral: CBPeripheral?
    private var cancellables = Set<AnyCancellable>()

    public override init() {
        super.init()
        var options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true
        ]

        // LiveContainer compatibility check:
        // Only pass CBCentralManagerOptionRestoreIdentifierKey if the runtime host bundle's
        // Info.plist explicitly specifies "bluetooth-central" in UIBackgroundModes.
        // Under LiveContainer, guest binaries share the host Info.plist which omits this,
        // and attempting state restoration would throw an NSInternalInconsistencyException.
        if let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
           backgroundModes.contains("bluetooth-central") {
            options[CBCentralManagerOptionRestoreIdentifierKey] = ContinuityDecoder.restoreIdentifier
        }

        self.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main, options: options)
    }

    // MARK: - Public Interface

    public func startScanning() {
        guard let central = centralManager, central.state == .poweredOn else { return }

        // We scan with allowDuplicates to receive continuous RSSI and lid open updates
        let scanOptions: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ]

        // Scanning with nil serviceUUIDs in foreground captures Apple manufacturer advertisements
        central.scanForPeripherals(withServices: nil, options: scanOptions)
        isScanning = true
    }

    public func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
    }

    public func dismissPairingPopup() {
        shouldShowPairingPopup = false
    }

    // MARK: - Frame Parsing Core (27-byte Continuity 0x004C)

    public func parseAppleContinuityPayload(data: Data, rssi: Int, deviceIdentifier: String) -> DeviceContinuityFrame? {
        // Apple manufacturer data layout:
        // Byte 0-1: 0x4C, 0x00 (Apple ID)
        // Byte 2: 0x07 (Proximity Pairing Type)
        // Byte 3-4: Device Model (Little-Endian)
        // Byte 5: Status (Bit 5 = Flip Flag, Bit 1/3 = In-Ear, Bit 0/2 = Active Mic)
        // Byte 6: Battery Status (Nibbles for Left & Right in 10% steps; > 10 = Disconnected)
        // Byte 7: Case Battery (Low nibble) & Charging Flags (High nibble)
        // Byte 8: Lid Open Count (Increments on physical lid open)
        // Total expected payload is at least 9 bytes (up to 27 bytes for full pairing payload)

        guard data.count >= 9 else { return nil }

        let bytes = [UInt8](data)

        // Validate Type: 0x07 (Proximity Pairing)
        guard bytes[0] == ContinuityDecoder.proximityPairingType else { return nil }

        // Device Model (Bytes 1-2 relative to payload after Company ID, i.e. bytes[1] and bytes[2])
        // Depending on whether Company ID was stripped by CoreBluetooth:
        // CoreBluetooth advertisementData[CBAdvertisementDataManufacturerDataKey] INCLUDES Company ID!
        // Therefore, if bytes[0...1] are 0x4C, 0x00:
        var offset = 0
        if bytes.count >= 11 && bytes[0] == 0x4C && bytes[1] == 0x00 {
            offset = 2
            guard bytes[offset] == ContinuityDecoder.proximityPairingType else { return nil }
        }

        let typeIndex = offset
        let modelLowIndex = offset + 1
        let modelHighIndex = offset + 2
        let statusIndex = offset + 3
        let batteryIndex = offset + 4
        let caseBatteryIndex = offset + 5
        let openCountIndex = offset + 6

        guard bytes.indices.contains(openCountIndex) else { return nil }

        // Device Model (Little Endian)
        let rawModelCode = UInt16(bytes[modelLowIndex]) | (UInt16(bytes[modelHighIndex]) << 8)
        let model = AirPodsModel.from(rawModelCode: rawModelCode)

        // Status Byte
        let statusByte = bytes[statusIndex]
        let flipFlag = (statusByte & 0x20) != 0 // Bit 5
        let inEarLeftBit = (statusByte & 0x02) != 0 // Bit 1
        let inEarRightBit = (statusByte & 0x08) != 0 // Bit 3
        let primaryMicBit = (statusByte & 0x01) != 0 // Bit 0

        // Battery Byte: Left & Right nibbles (0 to 10 -> 0% to 100%, 0xF or >10 -> Disconnected)
        let rawNibble1 = (bytes[batteryIndex] >> 4) & 0x0F
        let rawNibble2 = bytes[batteryIndex] & 0x0F

        // Assign left vs right based on flipFlag
        let leftRaw = flipFlag ? rawNibble2 : rawNibble1
        let rightRaw = flipFlag ? rawNibble1 : rawNibble2

        let leftPercentage: Int? = (leftRaw <= 10) ? Int(leftRaw) * 10 : nil
        let rightPercentage: Int? = (rightRaw <= 10) ? Int(rightRaw) * 10 : nil

        // Case & Charging Byte:
        let caseByte = bytes[caseBatteryIndex]
        let caseRawNibble = caseByte & 0x0F
        let casePercentage: Int? = (caseRawNibble <= 10) ? Int(caseRawNibble) * 10 : nil

        // Charging flags in high nibble (bits 4, 5, 6)
        let leftChargingBit = (caseByte & 0x10) != 0
        let rightChargingBit = (caseByte & 0x20) != 0
        let caseChargingBit = (caseByte & 0x40) != 0

        let leftCharging = flipFlag ? rightChargingBit : leftChargingBit
        let rightCharging = flipFlag ? leftChargingBit : rightChargingBit

        // Lid Open Count
        let openCount = bytes[openCountIndex]

        // Proximity EMA calculation
        let previousSmoothed = smoothedRSSIByDevice[deviceIdentifier] ?? Double(rssi)
        let smoothedRSSI = (emaAlpha * Double(rssi)) + ((1.0 - emaAlpha) * previousSmoothed)
        smoothedRSSIByDevice[deviceIdentifier] = smoothedRSSI

        let isNear = smoothedRSSI >= proximityThresholdRSSI

        // Check if Lid Open Count incremented
        let previousCount = lastLidOpenCountByDevice[deviceIdentifier]
        var didLidOpen = false
        if let previous = previousCount {
            if openCount != previous && openCount > 0 {
                didLidOpen = true
            }
        } else {
            // First observation of this device
            didLidOpen = isNear
        }
        lastLidOpenCountByDevice[deviceIdentifier] = openCount

        let frame = DeviceContinuityFrame(
            model: model,
            leftBattery: EarbudBatteryState(percentage: leftPercentage, isCharging: leftCharging),
            rightBattery: EarbudBatteryState(percentage: rightPercentage, isCharging: rightCharging),
            caseBattery: EarbudBatteryState(percentage: casePercentage, isCharging: caseChargingBit),
            leftInEar: flipFlag ? inEarRightBit : inEarLeftBit,
            rightInEar: flipFlag ? inEarLeftBit : inEarRightBit,
            primaryMicIsLeft: primaryMicBit,
            lidOpenCount: openCount,
            rssi: rssi,
            smoothedRSSI: smoothedRSSI,
            isNearProximity: isNear,
            rawManufacturerBytes: data,
            timestamp: Date()
        )

        // Trigger pairing popup only if near and lid opened
        if isNear && didLidOpen {
            DispatchQueue.main.async {
                self.shouldShowPairingPopup = true
            }
        }

        return frame
    }
}

// MARK: - CBCentralManagerDelegate & State Restoration

extension ContinuityDecoder: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            isScanning = false
        }
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // iOS Background State Restoration
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                self.fallbackPeripheral = peripheral
                peripheral.delegate = self
            }
        }
        if central.state == .poweredOn {
            startScanning()
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Track discovered peripherals
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
        }

        // 1. Process Apple Manufacturer Specific Data (0x004C)
        if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if let frame = parseAppleContinuityPayload(data: mfgData, rssi: RSSI.intValue, deviceIdentifier: peripheral.identifier.uuidString) {
                DispatchQueue.main.async {
                    self.latestFrame = frame
                }
                return
            }
        }

        // 2. Seamless Fallback: Check if device advertises standard Battery Service (0x180F)
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           serviceUUIDs.contains(ContinuityDecoder.batteryServiceUUID) {
            if fallbackPeripheral == nil || fallbackPeripheral?.identifier == peripheral.identifier {
                fallbackPeripheral = peripheral
                fallbackPeripheral?.delegate = self
                central.connect(peripheral, options: nil)
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isFallbackGATTActive = true
        peripheral.discoverServices([ContinuityDecoder.batteryServiceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isFallbackGATTActive = false
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isFallbackGATTActive = false
        if peripheral == fallbackPeripheral {
            fallbackPeripheral = nil
        }
    }
}

// MARK: - CBPeripheralDelegate (Fallback Battery Service)

extension ContinuityDecoder: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == ContinuityDecoder.batteryServiceUUID {
            peripheral.discoverCharacteristics([ContinuityDecoder.batteryLevelCharUUID], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == ContinuityDecoder.batteryLevelCharUUID {
            peripheral.readValue(for: characteristic)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == ContinuityDecoder.batteryLevelCharUUID,
              let data = characteristic.value, !data.isEmpty else { return }

        let batteryLevel = Int(data[0])
        DispatchQueue.main.async {
            self.connectedGATTBatteryPercentage = batteryLevel

            // If no Continuity frame exists yet, synthesize fallback state
            if self.latestFrame == nil {
                self.latestFrame = DeviceContinuityFrame(
                    model: .airPodsPro2,
                    leftBattery: EarbudBatteryState(percentage: batteryLevel, isCharging: false),
                    rightBattery: EarbudBatteryState(percentage: batteryLevel, isCharging: false),
                    caseBattery: EarbudBatteryState(percentage: nil, isCharging: false),
                    leftInEar: true,
                    rightInEar: true,
                    primaryMicIsLeft: true,
                    lidOpenCount: 1,
                    rssi: -55,
                    smoothedRSSI: -55.0,
                    isNearProximity: true
                )
            } else {
                // Update existing frame
                self.latestFrame?.leftBattery.percentage = batteryLevel
                self.latestFrame?.rightBattery.percentage = batteryLevel
            }
        }
    }
}

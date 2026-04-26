import Foundation
import CoreBluetooth

@available(iOS 13.0, macOS 10.15, *)
public struct AsyncDiscoveredPeripheral {
    public let peripheral: CBPeripheral
    public let advertisementData: [String: Any]
    public let rssi: NSNumber

    public init(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        self.peripheral = peripheral
        self.advertisementData = advertisementData
        self.rssi = rssi
    }
}

@available(iOS 13.0, macOS 10.15, *)
public struct AsyncScanRequest {
    public let serviceUUIDs: [CBUUID]?
    public let options: [String: Any]?
    public let matcher: ((AsyncDiscoveredPeripheral) -> Bool)?

    public init(
        serviceUUIDs: [CBUUID]? = nil,
        options: [String: Any]? = nil,
        matcher: ((AsyncDiscoveredPeripheral) -> Bool)? = nil
    ) {
        self.serviceUUIDs = serviceUUIDs
        self.options = options
        self.matcher = matcher
    }
}

@available(iOS 13.0, macOS 10.15, *)
public enum AsyncConnectTarget {
    case peripheral(CBPeripheral)
    case identifier(UUID)
    case matcher((AsyncDiscoveredPeripheral) -> Bool)
}

@available(iOS 13.0, macOS 10.15, *)
public struct AsyncConnectRequest {
    public let target: AsyncConnectTarget
    public let scanServiceUUIDs: [CBUUID]?
    public let scanOptions: [String: Any]?
    public let connectOptions: [String: Any]?
    public let timeout: TimeInterval

    public init(
        target: AsyncConnectTarget,
        scanServiceUUIDs: [CBUUID]? = nil,
        scanOptions: [String: Any]? = nil,
        connectOptions: [String: Any]? = nil,
        timeout: TimeInterval = 15
    ) {
        self.target = target
        self.scanServiceUUIDs = scanServiceUUIDs
        self.scanOptions = scanOptions
        self.connectOptions = connectOptions
        self.timeout = timeout
    }
}

@available(iOS 13.0, macOS 10.15, *)
public enum AsyncConnectionEvent {
    case connected(CBPeripheral)
    case disconnected(CBPeripheral, Error?)
}

/// 扫描操作的返回状态
@available(iOS 13.0, macOS 10.15, *)
public enum ScanAction {
    /// 跳过当前设备，继续扫描
    case skip
    /// 连接该设备，停止扫描
    case connect
}

@available(iOS 13.0, macOS 10.15, *)
public enum AsyncBleClientError: Error {
    public enum Operation {
        case connect
        case disconnect
        case discoverServices
        case discoverCharacteristics
        case readValue
        case writeValue
        case notifications
    }

    case bluetoothUnavailable(CBManagerState)
    case busy
    case timeout
    case peripheralNotFound(UUID)
    case invalidState(String)
    case connectFailed(CBPeripheral, Error?)
    case operationFailed(Operation, Error)
}

@available(iOS 13.0, macOS 10.15, *)
extension AsyncBleClientError.Operation {
    var label: String {
        switch self {
        case .connect:
            return "connect"
        case .disconnect:
            return "disconnect"
        case .discoverServices:
            return "discoverServices"
        case .discoverCharacteristics:
            return "discoverCharacteristics"
        case .readValue:
            return "readValue"
        case .writeValue:
            return "writeValue"
        case .notifications:
            return "notifications"
        }
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension AsyncBleClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let state):
            return "Bluetooth unavailable, current state: \(state.rawValue)"
        case .busy:
            return "Another BLE operation is already in progress"
        case .timeout:
            return "BLE operation timed out"
        case .peripheralNotFound(let identifier):
            return "Peripheral not found: \(identifier.uuidString)"
        case .invalidState(let message):
            return "Invalid BLE state: \(message)"
        case .connectFailed(let peripheral, let error):
            if let error = error {
                return "Failed to connect peripheral \(peripheral.identifier.uuidString): \(error.localizedDescription)"
            }
            return "Failed to connect peripheral \(peripheral.identifier.uuidString)"
        case .operationFailed(let operation, let error):
            return "BLE operation \(operation.label) failed: \(error.localizedDescription)"
        }
    }
}

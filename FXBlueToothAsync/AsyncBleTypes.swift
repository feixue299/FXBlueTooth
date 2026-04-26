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

@available(iOS 13.0, macOS 10.15, *)
public enum AsyncBleClientError: Error {
    case bluetoothUnavailable(CBManagerState)
    case busy
    case timeout
    case peripheralNotFound(UUID)
    case invalidState(String)
    case connectFailed(CBPeripheral, Error?)
}

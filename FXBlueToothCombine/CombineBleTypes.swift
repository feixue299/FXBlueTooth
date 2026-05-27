import Foundation
import CoreBluetooth
import FXBlueToothCore

@available(iOS 13.0, macOS 10.15, *)
public struct DiscoveredPeripheral {
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
public enum ConnectionEvent {
    case connected(CBPeripheral)
    case disconnected(any PeripheralProtocol, Error?)
}

@available(iOS 13.0, macOS 10.15, *)
public enum BleError: Error {
    public enum Operation: String {
        case connect, disconnect, discoverServices, discoverCharacteristics
        case readValue, writeValue, notifications
    }

    case bluetoothUnavailable(CBManagerState)
    case timeout(Operation)
    case connectFailed(CBPeripheral, Error?)
    case disconnected(any PeripheralProtocol, Error?)
    case operationFailed(Operation, Error)
    case cancelled
}

@available(iOS 13.0, macOS 10.15, *)
extension BleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let s): return "Bluetooth unavailable, state: \(s.rawValue)"
        case .timeout(let op): return "BLE operation \(op.rawValue) timed out"
        case .connectFailed(let p, let e):
            return "Connect failed for \(p.identifier): \(e?.localizedDescription ?? "unknown")"
        case .disconnected(let p, let e):
            return "Disconnected \(p.identifier): \(e?.localizedDescription ?? "no error")"
        case .operationFailed(let op, let e):
            return "BLE \(op.rawValue) failed: \(e.localizedDescription)"
        case .cancelled: return "BLE operation cancelled"
        }
    }
}

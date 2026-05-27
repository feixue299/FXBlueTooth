import Foundation
import CoreBluetooth
import FXBlueToothCore
@testable import FXBlueToothCombine

@available(iOS 13.0, macOS 10.15, *)
final class MockPeripheral: NSObject, PeripheralProtocol {

    @objc dynamic var identifier: UUID = UUID()

    private var _services: [CBService]? = nil
    var services: [CBService]? {
        get { _services }
        set { _services = newValue }
    }

    @objc dynamic var delegate: CBPeripheralDelegate? = nil
    var peripheralDelegate: CBPeripheralDelegate? {
        get { delegate }
        set { delegate = newValue }
    }

    // Call records
    var discoverServicesCalledWith: [CBUUID]?? = nil
    var discoverCharacteristicsCalledFor: CBUUID? = nil
    var readValueCalledFor: CBUUID? = nil
    var writeValueCalledFor: CBUUID? = nil
    var writeValueTypeCalledWith: CBCharacteristicWriteType? = nil
    var setNotifyCalledFor: CBUUID? = nil
    var setNotifyEnabled: Bool? = nil
    var setNotifyLog: [(CBUUID, Bool)] = []
    var operationLog: [String] = []

    // Auto-callback flags
    var autoCallbackDiscoverServices: Bool = true
    var autoCallbackDiscoverCharacteristics: Bool = true
    var autoCallbackReadValue: Bool = true
    var autoCallbackWriteValue: Bool = true

    // Injected behavior
    var discoverServicesError: Error? = nil
    var discoverCharacteristicsError: Error? = nil
    var readValueResultByUUID: [CBUUID: Result<Data, Error>] = [:]
    var writeValueErrorByUUID: [CBUUID: Error] = [:]
    var notificationDataOnEnable: Data? = nil

    func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        discoverServicesCalledWith = .some(serviceUUIDs)
        guard autoCallbackDiscoverServices else { return }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            (self.peripheralDelegate as? PeripheralDelegateBridge)?
                .handleDidDiscoverServices(error: self.discoverServicesError)
        }
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {
        discoverCharacteristicsCalledFor = service.uuid
        guard autoCallbackDiscoverCharacteristics else { return }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            (self.peripheralDelegate as? PeripheralDelegateBridge)?
                .handleDidDiscoverCharacteristics(for: service, error: self.discoverCharacteristicsError)
        }
    }

    func readValue(for characteristic: CBCharacteristic) {
        readValueCalledFor = characteristic.uuid
        guard autoCallbackReadValue else { return }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            let bridge = self.peripheralDelegate as? PeripheralDelegateBridge
            let callbackCharacteristic = CBMutableCharacteristic(
                type: characteristic.uuid,
                properties: characteristic.properties,
                value: nil,
                permissions: [.readable, .writeable]
            )
            if let result = self.readValueResultByUUID[characteristic.uuid] {
                switch result {
                case .success(let data):
                    callbackCharacteristic.value = data
                    bridge?.handleDidUpdateValue(for: callbackCharacteristic, error: nil)
                case .failure(let err):
                    bridge?.handleDidUpdateValue(for: callbackCharacteristic, error: err)
                }
            } else {
                callbackCharacteristic.value = characteristic.value
                bridge?.handleDidUpdateValue(for: callbackCharacteristic, error: nil)
            }
        }
    }

    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        writeValueCalledFor = characteristic.uuid
        writeValueTypeCalledWith = type
        operationLog.append("write:\(characteristic.uuid.uuidString)")
        guard autoCallbackWriteValue, type == .withResponse else { return }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            (self.peripheralDelegate as? PeripheralDelegateBridge)?
                .handleDidWriteValue(for: characteristic,
                                     error: self.writeValueErrorByUUID[characteristic.uuid])
        }
    }

    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {
        setNotifyCalledFor = characteristic.uuid
        setNotifyEnabled = enabled
        setNotifyLog.append((characteristic.uuid, enabled))
        operationLog.append("notify:\(enabled):\(characteristic.uuid.uuidString)")
        if enabled, let notificationDataOnEnable {
            push(notification: notificationDataOnEnable, for: characteristic)
        }
    }

    /// Test helper: push a notification value
    func push(notification data: Data, for characteristic: CBCharacteristic) {
        let cb = CBMutableCharacteristic(type: characteristic.uuid,
                                         properties: [.notify],
                                         value: data,
                                         permissions: [])
        (peripheralDelegate as? PeripheralDelegateBridge)?
            .handleDidUpdateValue(for: cb, error: nil)
    }
}

import Foundation
import CoreBluetooth
@testable import FXBlueToothAsync

/// 测试用 MockPeripheral，实现 PeripheralProtocol
@available(iOS 13.0, macOS 10.15, *)
final class MockPeripheral: NSObject, PeripheralProtocol {

    var identifier: UUID = UUID()

    // 可在测试中设置的 services（CBMutableService 是 CBService 子类，可被实例化）
    private var _services: [CBService]? = nil
    var services: [CBService]? {
        get { _services }
        set { _services = newValue }
    }

    // 提供 delegate selector，兼容将该对象按 CBPeripheral 使用时的 delegate 读写。
    @objc dynamic var delegate: CBPeripheralDelegate? = nil
    var peripheralDelegate: CBPeripheralDelegate? {
        get { delegate }
        set { delegate = newValue }
    }

    // 调用记录
    var discoverServicesCalledWith: [CBUUID]?? = nil   // nil = 未调用；.some(nil) = 以 nil 调用
    var discoverCharacteristicsCalledFor: CBUUID? = nil
    var readValueCalledFor: CBUUID? = nil
    var writeValueCalledFor: CBUUID? = nil
    var setNotifyCalledFor: CBUUID? = nil
    var setNotifyEnabled: Bool? = nil

    // 自动回调开关（默认模拟真实设备行为）
    var autoCallbackDiscoverServices: Bool = true
    var autoCallbackDiscoverCharacteristics: Bool = true
    var autoCallbackReadValue: Bool = true
    var autoCallbackWriteValue: Bool = true
    var autoCallbackNotificationsOnSubscribe: Bool = false

    // 行为注入
    var discoverServicesError: Error? = nil
    var discoverCharacteristicsError: Error? = nil
    var readValueResultByUUID: [CBUUID: Result<Data, Error>] = [:]
    var writeValueErrorByUUID: [CBUUID: Error] = [:]
    var notificationValuesByUUID: [CBUUID: [Data]] = [:]
    var notificationIntervalNanoseconds: UInt64 = 5_000_000

    func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        discoverServicesCalledWith = .some(serviceUUIDs)
        guard autoCallbackDiscoverServices else { return }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            self.notifyDiscoverServices(error: self.discoverServicesError)
        }
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {
        discoverCharacteristicsCalledFor = service.uuid
        guard autoCallbackDiscoverCharacteristics else { return }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            self.notifyDiscoverCharacteristics(for: service, error: self.discoverCharacteristicsError)
        }
    }

    func readValue(for characteristic: CBCharacteristic) {
        readValueCalledFor = characteristic.uuid
        guard autoCallbackReadValue else { return }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            if let result = self.readValueResultByUUID[characteristic.uuid] {
                switch result {
                case .success(let data):
                    self.notifyReadValue(for: characteristic, data: data, error: nil)
                case .failure(let error):
                    self.notifyReadValue(for: characteristic, data: nil, error: error)
                }
            } else {
                self.notifyReadValue(for: characteristic, data: characteristic.value, error: nil)
            }
        }
    }

    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        writeValueCalledFor = characteristic.uuid
        guard autoCallbackWriteValue, type == .withResponse else { return }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            self.notifyWriteValue(for: characteristic, error: self.writeValueErrorByUUID[characteristic.uuid])
        }
    }

    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {
        setNotifyCalledFor = characteristic.uuid
        setNotifyEnabled = enabled

        guard enabled, autoCallbackNotificationsOnSubscribe else { return }
        let values = notificationValuesByUUID[characteristic.uuid] ?? []
        for (index, value) in values.enumerated() {
            Task {
                let delay = UInt64(index + 1) * self.notificationIntervalNanoseconds
                try? await Task.sleep(nanoseconds: delay)
                self.notifyNotificationValue(for: characteristic.uuid, data: value)
            }
        }
    }

    // MARK: - Delegate Notifications

    private func notifyDiscoverServices(error: Error? = nil) {
        guard let delegate = peripheralDelegate as? AsyncPeripheral else { return }
        delegate.handleDidDiscoverServices(error: error)
    }

    private func notifyDiscoverCharacteristics(for service: CBService, error: Error? = nil) {
        guard let delegate = peripheralDelegate as? AsyncPeripheral else { return }
        delegate.handleDidDiscoverCharacteristics(for: service, error: error)
    }

    private func notifyReadValue(for characteristic: CBCharacteristic, data: Data? = nil, error: Error? = nil) {
        guard let delegate = peripheralDelegate as? AsyncPeripheral else { return }
        let callbackCharacteristic = CBMutableCharacteristic(
            type: characteristic.uuid,
            properties: characteristic.properties,
            value: data,
            permissions: [.readable, .writeable]
        )
        delegate.handleDidUpdateValue(for: callbackCharacteristic, error: error)
    }

    private func notifyWriteValue(for characteristic: CBCharacteristic, error: Error? = nil) {
        guard let delegate = peripheralDelegate as? AsyncPeripheral else { return }
        delegate.handleDidWriteValue(for: characteristic, error: error)
    }

    private func notifyNotificationValue(for characteristicUUID: CBUUID, data: Data) {
        guard let delegate = peripheralDelegate as? AsyncPeripheral else { return }
        let callbackCharacteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.notify],
            value: data,
            permissions: []
        )
        delegate.handleDidUpdateValue(for: callbackCharacteristic, error: nil)
    }
}

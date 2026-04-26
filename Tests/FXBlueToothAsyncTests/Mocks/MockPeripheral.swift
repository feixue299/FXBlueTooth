import Foundation
import CoreBluetooth
@testable import FXBlueToothAsync

/// 测试用 MockPeripheral，实现 PeripheralProtocol
@available(iOS 13.0, macOS 10.15, *)
final class MockPeripheral: PeripheralProtocol {

    var identifier: UUID = UUID()

    // 可在测试中设置的 services（CBMutableService 是 CBService 子类，可被实例化）
    private var _services: [CBService]? = nil
    var services: [CBService]? {
        get { _services }
        set { _services = newValue }
    }

    var peripheralDelegate: CBPeripheralDelegate? = nil

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

    // 行为注入
    var discoverServicesError: Error? = nil
    var discoverCharacteristicsError: Error? = nil
    var readValueResultByUUID: [CBUUID: Result<Data, Error>] = [:]
    var writeValueErrorByUUID: [CBUUID: Error] = [:]

    func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        discoverServicesCalledWith = .some(serviceUUIDs)
        guard autoCallbackDiscoverServices else { return }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            self.emitDiscoverServices(error: self.discoverServicesError)
        }
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {
        discoverCharacteristicsCalledFor = service.uuid
        guard autoCallbackDiscoverCharacteristics else { return }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            self.emitDiscoverCharacteristics(for: service, error: self.discoverCharacteristicsError)
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
                    self.emitReadValue(for: characteristic, data: data, error: nil)
                case .failure(let error):
                    self.emitReadValue(for: characteristic, data: nil, error: error)
                }
            } else {
                self.emitReadValue(for: characteristic, data: characteristic.value, error: nil)
            }
        }
    }

    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        writeValueCalledFor = characteristic.uuid
        guard autoCallbackWriteValue, type == .withResponse else { return }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            self.emitWriteValue(for: characteristic, error: self.writeValueErrorByUUID[characteristic.uuid])
        }
    }

    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {
        setNotifyCalledFor = characteristic.uuid
        setNotifyEnabled = enabled
    }

    // MARK: - Manual Emit

    func emitDiscoverServices(error: Error? = nil) {
        guard let delegate = peripheralDelegate as? AsyncPeripheral else { return }
        delegate.handleDidDiscoverServices(error: error)
    }

    func emitDiscoverCharacteristics(for service: CBService, error: Error? = nil) {
        guard let delegate = peripheralDelegate as? AsyncPeripheral else { return }
        delegate.handleDidDiscoverCharacteristics(for: service, error: error)
    }

    func emitReadValue(for characteristic: CBCharacteristic, data: Data? = nil, error: Error? = nil) {
        guard let delegate = peripheralDelegate as? AsyncPeripheral else { return }
        let callbackCharacteristic = CBMutableCharacteristic(
            type: characteristic.uuid,
            properties: characteristic.properties,
            value: data,
            permissions: [.readable, .writeable]
        )
        delegate.handleDidUpdateValue(for: callbackCharacteristic, error: error)
    }

    func emitWriteValue(for characteristic: CBCharacteristic, error: Error? = nil) {
        guard let delegate = peripheralDelegate as? AsyncPeripheral else { return }
        delegate.handleDidWriteValue(for: characteristic, error: error)
    }

    func emitNotificationValue(for characteristicUUID: CBUUID, data: Data) {
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

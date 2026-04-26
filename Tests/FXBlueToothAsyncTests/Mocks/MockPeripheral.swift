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

    func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        discoverServicesCalledWith = .some(serviceUUIDs)
    }

    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {
        discoverCharacteristicsCalledFor = service.uuid
    }

    func readValue(for characteristic: CBCharacteristic) {
        readValueCalledFor = characteristic.uuid
    }

    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        writeValueCalledFor = characteristic.uuid
    }

    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {
        setNotifyCalledFor = characteristic.uuid
        setNotifyEnabled = enabled
    }
}

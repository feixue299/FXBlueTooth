import Foundation
import CoreBluetooth

/// CBPeripheral 的可测试抽象
/// 生产代码使用真实 CBPeripheral，测试代码注入 MockPeripheral
@available(iOS 13.0, macOS 10.15, *)
public protocol PeripheralProtocol: AnyObject {
    var identifier: UUID { get }
    var services: [CBService]? { get }
    var peripheralDelegate: CBPeripheralDelegate? { get set }
    func discoverServices(_ serviceUUIDs: [CBUUID]?)
    func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService)
    func readValue(for characteristic: CBCharacteristic)
    func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType)
    func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic)
}

@available(iOS 13.0, macOS 10.15, *)
extension CBPeripheral: PeripheralProtocol {
    public var peripheralDelegate: CBPeripheralDelegate? {
        get { delegate }
        set { delegate = newValue }
    }
}

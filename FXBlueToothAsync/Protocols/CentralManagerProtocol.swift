import Foundation
import CoreBluetooth

/// CBCentralManager 的可测试抽象
/// 生产代码使用真实 CBCentralManager，测试代码注入 MockCentralManager
@available(iOS 13.0, macOS 10.15, *)
public protocol CentralManagerProtocol: AnyObject {
    var state: CBManagerState { get }
    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?)
    func stopScan()
    func connect(_ peripheral: CBPeripheral, options: [String: Any]?)
    func cancelPeripheralConnection(_ peripheral: CBPeripheral)
}

@available(iOS 13.0, macOS 10.15, *)
extension CBCentralManager: CentralManagerProtocol {}

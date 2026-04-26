import Foundation
import CoreBluetooth
@testable import FXBlueToothAsync

/// 测试用 MockCentralManager，实现 CentralManagerProtocol
@available(iOS 13.0, macOS 10.15, *)
final class MockCentralManager: CentralManagerProtocol {

    // 可控制的状态
    var state: CBManagerState = .poweredOff

    // 调用记录
    var scanCalledWithServices: [CBUUID]? = nil
    var scanWasCalled = false
    var stopScanCalled = false
    var connectCalledWith: CBPeripheral? = nil
    var cancelConnectionCalledWith: CBPeripheral? = nil

    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {
        scanWasCalled = true
        scanCalledWithServices = serviceUUIDs
    }

    func stopScan() {
        stopScanCalled = true
    }

    func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {
        connectCalledWith = peripheral
    }

    func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
        cancelConnectionCalledWith = peripheral
    }
}

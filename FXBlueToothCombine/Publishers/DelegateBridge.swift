import Foundation
import Combine
import CoreBluetooth
import FXBlueToothCore

/// 把 CBCentralManagerDelegate 的所有回调扇出到独立的 Subject 上
@available(iOS 13.0, macOS 10.15, *)
final class CentralDelegateBridge: NSObject, CBCentralManagerDelegate {
    let stateSubject = CurrentValueSubject<CBManagerState, Never>(.unknown)
    let didDiscover = PassthroughSubject<DiscoveredPeripheral, Never>()
    let didConnect = PassthroughSubject<CBPeripheral, Never>()
    let didFailToConnect = PassthroughSubject<(CBPeripheral, Error?), Never>()
    /// any PeripheralProtocol 以兼容测试 mock；生产为 CBPeripheral
    let didDisconnect = PassthroughSubject<(any PeripheralProtocol, Error?), Never>()

    weak var manager: CombineBleManager?

    override init() { super.init() }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stateSubject.send(manager?.centralState ?? central.state)
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        didDiscover.send(DiscoveredPeripheral(
            peripheral: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI
        ))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        didConnect.send(peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        didFailToConnect.send((peripheral, error))
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        didDisconnect.send((peripheral, error))
    }

    /// 测试 Mock 走非 CBPeripheral 路径时调用
    func handleDidDisconnect(peripheral: any PeripheralProtocol, error: Error?) {
        didDisconnect.send((peripheral, error))
    }
}

/// 把 CBPeripheralDelegate 的所有回调扇出到独立的 Subject 上
@available(iOS 13.0, macOS 10.15, *)
final class PeripheralDelegateBridge: NSObject, CBPeripheralDelegate {
    let didDiscoverServices = PassthroughSubject<Error?, Never>()
    let didDiscoverCharacteristics = PassthroughSubject<(CBService, Error?), Never>()
    let didUpdateValue = PassthroughSubject<(CBCharacteristic, Error?), Never>()
    let didWriteValue = PassthroughSubject<(CBCharacteristic, Error?), Never>()
    let didUpdateNotificationState = PassthroughSubject<(CBCharacteristic, Error?), Never>()

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        didDiscoverServices.send(error)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        didDiscoverCharacteristics.send((service, error))
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        didUpdateValue.send((characteristic, error))
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        didWriteValue.send((characteristic, error))
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        didUpdateNotificationState.send((characteristic, error))
    }

    // MARK: - Test mock entry points
    func handleDidDiscoverServices(error: Error?) { didDiscoverServices.send(error) }
    func handleDidDiscoverCharacteristics(for service: CBService, error: Error?) {
        didDiscoverCharacteristics.send((service, error))
    }
    func handleDidUpdateValue(for c: CBCharacteristic, error: Error?) { didUpdateValue.send((c, error)) }
    func handleDidWriteValue(for c: CBCharacteristic, error: Error?) { didWriteValue.send((c, error)) }
    func handleDidUpdateNotificationState(for c: CBCharacteristic, error: Error?) {
        didUpdateNotificationState.send((c, error))
    }
}

import Foundation
import Combine
import CoreBluetooth
import FXBlueToothCore

/// Combine 风格的已连接外设
///
/// 所有方法返回 `AnyPublisher`，订阅时发起底层调用，对应回调到达后 complete
@available(iOS 13.0, macOS 10.15, *)
public final class CombinePeripheral {

    public let peripheral: any PeripheralProtocol
    private let queue: DispatchQueue
    let bridge: PeripheralDelegateBridge

    public init(peripheral: any PeripheralProtocol,
                queue: DispatchQueue = DispatchQueue(label: "FXBlueToothCombine.peripheral")) {
        self.peripheral = peripheral
        self.queue = queue
        self.bridge = PeripheralDelegateBridge()
        self.peripheral.peripheralDelegate = bridge
    }

    // MARK: - Discover

    public func discoverServices(_ uuids: [CBUUID]? = nil,
                                 timeout: TimeInterval? = nil)
    -> AnyPublisher<[CBService], BleError> {
        let bridge = self.bridge
        let peripheral = self.peripheral
        let pub = bridge.didDiscoverServices
            .first()
            .tryMap { (error: Error?) -> [CBService] in
                if let e = error { throw BleError.operationFailed(.discoverServices, e) }
                return peripheral.services ?? []
            }
            .mapError { Self.bleError($0, op: .discoverServices) }
            .handleEvents(receiveSubscription: { _ in
                peripheral.discoverServices(uuids)
            })
            .eraseToAnyPublisher()
        return CombineBleManager.applyTimeout(pub, timeout: timeout,
                                              op: .discoverServices, queue: queue)
    }

    public func discoverCharacteristics(_ uuids: [CBUUID]? = nil,
                                        for service: CBService,
                                        timeout: TimeInterval? = nil)
    -> AnyPublisher<[CBCharacteristic], BleError> {
        let bridge = self.bridge
        let peripheral = self.peripheral
        let targetUUID = service.uuid
        let pub = bridge.didDiscoverCharacteristics
            .filter { $0.0.uuid == targetUUID }
            .first()
            .tryMap { (svc, error) -> [CBCharacteristic] in
                if let e = error { throw BleError.operationFailed(.discoverCharacteristics, e) }
                return svc.characteristics ?? []
            }
            .mapError { Self.bleError($0, op: .discoverCharacteristics) }
            .handleEvents(receiveSubscription: { _ in
                peripheral.discoverCharacteristics(uuids, for: service)
            })
            .eraseToAnyPublisher()
        return CombineBleManager.applyTimeout(pub, timeout: timeout,
                                              op: .discoverCharacteristics, queue: queue)
    }

    // MARK: - Read / Write

    public func read(_ characteristic: CBCharacteristic,
                     timeout: TimeInterval? = nil)
    -> AnyPublisher<Data, BleError> {
        let bridge = self.bridge
        let peripheral = self.peripheral
        let target = characteristic.uuid
        let pub = bridge.didUpdateValue
            .filter { $0.0.uuid == target }
            .first()
            .tryMap { (c, error) -> Data in
                if let e = error { throw BleError.operationFailed(.readValue, e) }
                return c.value ?? Data()
            }
            .mapError { Self.bleError($0, op: .readValue) }
            .handleEvents(receiveSubscription: { _ in
                peripheral.readValue(for: characteristic)
            })
            .eraseToAnyPublisher()
        return CombineBleManager.applyTimeout(pub, timeout: timeout,
                                              op: .readValue, queue: queue)
    }

    public func writeWithResponse(_ data: Data,
                                  to characteristic: CBCharacteristic,
                                  timeout: TimeInterval? = nil)
    -> AnyPublisher<Void, BleError> {
        let bridge = self.bridge
        let peripheral = self.peripheral
        let target = characteristic.uuid
        let pub = bridge.didWriteValue
            .filter { $0.0.uuid == target }
            .first()
            .tryMap { (_, error) -> Void in
                if let e = error { throw BleError.operationFailed(.writeValue, e) }
                return ()
            }
            .mapError { Self.bleError($0, op: .writeValue) }
            .handleEvents(receiveSubscription: { _ in
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
            })
            .eraseToAnyPublisher()
        return CombineBleManager.applyTimeout(pub, timeout: timeout,
                                              op: .writeValue, queue: queue)
    }

    /// 无回调写：订阅时立即下发到底层并以 `Just(())` 完成
    public func writeWithoutResponse(_ data: Data,
                                     to characteristic: CBCharacteristic)
    -> AnyPublisher<Void, BleError> {
        let peripheral = self.peripheral
        return Deferred {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            return Just(()).setFailureType(to: BleError.self)
        }.eraseToAnyPublisher()
    }

    // MARK: - Notifications

    /// 订阅特征值通知。每次订阅独立调用 `setNotifyValue(true)`，
    /// 取消时调用 `setNotifyValue(false)`。多订阅者可通过用户层 `.share()` 复用
    public func notifications(for characteristic: CBCharacteristic)
    -> AnyPublisher<Data, BleError> {
        let bridge = self.bridge
        let peripheral = self.peripheral
        let target = characteristic.uuid
        return Deferred {
            bridge.didUpdateValue
                .filter { $0.0.uuid == target }
                .tryMap { (c, error) -> Data in
                    if let e = error { throw BleError.operationFailed(.notifications, e) }
                    return c.value ?? Data()
                }
                .mapError { Self.bleError($0, op: .notifications) }
                .handleEvents(
                    receiveSubscription: { _ in
                        peripheral.setNotifyValue(true, for: characteristic)
                    },
                    receiveCancel: {
                        peripheral.setNotifyValue(false, for: characteristic)
                    }
                )
        }.eraseToAnyPublisher()
    }

    // MARK: - Helpers

    private static func bleError(_ error: Error, op: BleError.Operation) -> BleError {
        (error as? BleError) ?? .operationFailed(op, error)
    }
}

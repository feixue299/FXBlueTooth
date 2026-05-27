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
    private let notificationLock = NSLock()
    private var notificationSubscriberCounts: [CBUUID: Int] = [:]

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

    /// 先订阅通知，再使用无响应写入发送命令，并等待写入后首个匹配的通知应答。
    ///
    /// 功能码和帧结构属于业务协议，调用方通过 `matcher` 判断通知数据是否为本次应答。
    /// 此 API 适用于设备通过 notify 对 writeWithoutResponse 命令返回业务响应的场景。
    public func writeWithoutResponse(_ data: Data,
                                     to writeCharacteristic: CBCharacteristic,
                                     awaiting notificationCharacteristic: CBCharacteristic,
                                     timeout: TimeInterval? = nil,
                                     matching matcher: @escaping (Data) -> Bool)
    -> AnyPublisher<Data, BleError> {
        Deferred { [weak self] () -> AnyPublisher<Data, BleError> in
            guard let self else {
                return Fail(error: BleError.cancelled).eraseToAnyPublisher()
            }

            let gate = NotificationResponseGate(matcher: matcher)
            let response = self.notifications(for: notificationCharacteristic)
                .filter { gate.accepts($0) }
                .first()
                .handleEvents(receiveSubscription: { _ in
                    self.peripheral.writeValue(data, for: writeCharacteristic, type: .withoutResponse)
                    gate.markWriteCompleted()
                })
                .eraseToAnyPublisher()

            return CombineBleManager.applyTimeout(response,
                                                  timeout: timeout,
                                                  op: .notifications,
                                                  queue: self.queue)
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Notifications

    /// 订阅特征值通知。同一 characteristic 的订阅会共享底层 notify 状态，
    /// 第一个订阅启用通知，最后一个订阅取消时关闭通知。
    public func notifications(for characteristic: CBCharacteristic)
    -> AnyPublisher<Data, BleError> {
        let bridge = self.bridge
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
                    receiveSubscription: { [weak self] _ in
                        self?.beginNotifications(for: characteristic)
                    },
                    receiveCompletion: { _ in
                        self.endNotifications(for: characteristic)
                    },
                    receiveCancel: {
                        self.endNotifications(for: characteristic)
                    }
                )
        }.eraseToAnyPublisher()
    }

    // MARK: - Helpers

    private func beginNotifications(for characteristic: CBCharacteristic) {
        notificationLock.lock()
        let count = notificationSubscriberCounts[characteristic.uuid, default: 0]
        notificationSubscriberCounts[characteristic.uuid] = count + 1
        notificationLock.unlock()

        if count == 0 {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    private func endNotifications(for characteristic: CBCharacteristic) {
        notificationLock.lock()
        let count = notificationSubscriberCounts[characteristic.uuid, default: 0]
        guard count > 0 else {
            notificationLock.unlock()
            return
        }
        let nextCount = count - 1
        if nextCount == 0 {
            notificationSubscriberCounts.removeValue(forKey: characteristic.uuid)
        } else {
            notificationSubscriberCounts[characteristic.uuid] = nextCount
        }
        notificationLock.unlock()

        if nextCount == 0 {
            peripheral.setNotifyValue(false, for: characteristic)
        }
    }

    private static func bleError(_ error: Error, op: BleError.Operation) -> BleError {
        (error as? BleError) ?? .operationFailed(op, error)
    }
}

private final class NotificationResponseGate {
    private let lock = NSLock()
    private let matcher: (Data) -> Bool
    private var writeCompleted = false

    init(matcher: @escaping (Data) -> Bool) {
        self.matcher = matcher
    }

    func markWriteCompleted() {
        lock.lock()
        writeCompleted = true
        lock.unlock()
    }

    func accepts(_ data: Data) -> Bool {
        lock.lock()
        let mayMatch = writeCompleted
        lock.unlock()
        return mayMatch && matcher(data)
    }
}

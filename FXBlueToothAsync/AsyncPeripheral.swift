import Foundation
import CoreBluetooth

/// 已连接的设备对象，提供所有 I/O 操作
@available(iOS 13.0, macOS 10.15, *)
public final class AsyncPeripheral: NSObject, CBPeripheralDelegate {

    // 内部使用 Protocol 类型，允许测试注入 MockPeripheral
    let _peripheral: any PeripheralProtocol

    private var discoverServicesContinuation: CheckedContinuation<[CBService], Error>?
    private var discoverCharacteristicsContinuations: [CBUUID: CheckedContinuation<[CBCharacteristic], Error>] = [:]
    private var readContinuations: [CBUUID: CheckedContinuation<Data, Error>] = [:]
    private var writeContinuations: [CBUUID: CheckedContinuation<Void, Error>] = [:]
    private var notifyContinuations: [CBUUID: AsyncThrowingStream<Data, Error>.Continuation] = [:]

    // MARK: - Init

    public init(peripheral: CBPeripheral) {
        self._peripheral = peripheral
        super.init()
        peripheral.peripheralDelegate = self
    }

    /// 测试专用初始化，注入 MockPeripheral
    init(peripheral: any PeripheralProtocol) {
        self._peripheral = peripheral
        super.init()
        peripheral.peripheralDelegate = self
    }

    // MARK: - Service & Characteristic Discovery

    /// 发现服务
    public func discover(
        serviceUUIDs: [CBUUID]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> [CBService] {
        guard discoverServicesContinuation == nil else {
            throw AsyncBleClientError.busy
        }

        return try await runWithTimeout(timeout) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.discoverServicesContinuation = continuation
                    self._peripheral.discoverServices(serviceUUIDs)
                }
            } onCancel: {
                self.discoverServicesContinuation?.resume(throwing: CancellationError())
                self.discoverServicesContinuation = nil
            }
        }
    }

    /// 为 service 发现 characteristics
    public func discover(
        characteristicUUIDs: [CBUUID]? = nil,
        for service: CBService,
        timeout: TimeInterval? = nil
    ) async throws -> [CBCharacteristic] {
        if discoverCharacteristicsContinuations[service.uuid] != nil {
            throw AsyncBleClientError.busy
        }

        let serviceUUID = service.uuid
        return try await runWithTimeout(timeout) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.discoverCharacteristicsContinuations[serviceUUID] = continuation
                    self._peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
                }
            } onCancel: {
                self.discoverCharacteristicsContinuations.removeValue(forKey: serviceUUID)?.resume(throwing: CancellationError())
            }
        }
    }

    // MARK: - Read/Write

    /// 读取 characteristic 的值
    public func read(
        for characteristic: CBCharacteristic,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        if readContinuations[characteristic.uuid] != nil {
            throw AsyncBleClientError.busy
        }

        let uuid = characteristic.uuid
        return try await runWithTimeout(timeout) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.readContinuations[uuid] = continuation
                    self._peripheral.readValue(for: characteristic)
                }
            } onCancel: {
                self.readContinuations.removeValue(forKey: uuid)?.resume(throwing: CancellationError())
            }
        }
    }

    /// 写入数据到 characteristic
    public func write(
        _ data: Data,
        to characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType = .withResponse,
        timeout: TimeInterval? = nil
    ) async throws {
        if type == .withoutResponse {
            _peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            return
        }

        if writeContinuations[characteristic.uuid] != nil {
            throw AsyncBleClientError.busy
        }

        let uuid = characteristic.uuid
        try await runWithTimeout(timeout) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.writeContinuations[uuid] = continuation
                    self._peripheral.writeValue(data, for: characteristic, type: .withResponse)
                }
            } onCancel: {
                self.writeContinuations.removeValue(forKey: uuid)?.resume(throwing: CancellationError())
            }
        }
    }

    // MARK: - Notifications

    /// 订阅 characteristic 的通知
    public func notifications(
        for characteristic: CBCharacteristic,
        bufferingPolicy: AsyncThrowingStream<Data, Error>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream(Data.self, bufferingPolicy: bufferingPolicy) { continuation in
            self.notifyContinuations[characteristic.uuid] = continuation
            self._peripheral.setNotifyValue(true, for: characteristic)

            continuation.onTermination = { [weak self] _ in
                Task {
                    self?.notifyContinuations.removeValue(forKey: characteristic.uuid)
                    self?._peripheral.setNotifyValue(false, for: characteristic)
                }
            }
        }
    }

    // MARK: - CBPeripheralDelegate (转发到 handle 方法)

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        handleDidDiscoverServices(error: error)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        handleDidDiscoverCharacteristics(for: service, error: error)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        handleDidUpdateValue(for: characteristic, error: error)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        handleDidWriteValue(for: characteristic, error: error)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        handleDidUpdateNotificationState(for: characteristic, error: error)
    }

    // MARK: - Internal Handlers（可在测试中直接调用）

    func handleDidDiscoverServices(error: Error?) {
        let services = _peripheral.services ?? []
        if let error = error {
            discoverServicesContinuation?.resume(throwing: AsyncBleClientError.operationFailed(.discoverServices, error))
        } else {
            discoverServicesContinuation?.resume(returning: services)
        }
        discoverServicesContinuation = nil
    }

    func handleDidDiscoverCharacteristics(for service: CBService, error: Error?) {
        guard let continuation = discoverCharacteristicsContinuations.removeValue(forKey: service.uuid) else { return }
        let characteristics = service.characteristics ?? []
        if let error = error {
            continuation.resume(throwing: AsyncBleClientError.operationFailed(.discoverCharacteristics, error))
        } else {
            continuation.resume(returning: characteristics)
        }
    }

    func handleDidUpdateValue(for characteristic: CBCharacteristic, error: Error?) {
        // 读操作
        if let continuation = readContinuations.removeValue(forKey: characteristic.uuid) {
            if let error = error {
                continuation.resume(throwing: AsyncBleClientError.operationFailed(.readValue, error))
            } else {
                continuation.resume(returning: characteristic.value ?? Data())
            }
        }

        // 通知订阅
        if let notifyContinuation = notifyContinuations[characteristic.uuid] {
            if let error = error {
                notifyContinuation.finish(throwing: AsyncBleClientError.operationFailed(.notifications, error))
                notifyContinuations.removeValue(forKey: characteristic.uuid)
            } else {
                notifyContinuation.yield(characteristic.value ?? Data())
            }
        }
    }

    func handleDidWriteValue(for characteristic: CBCharacteristic, error: Error?) {
        guard let continuation = writeContinuations.removeValue(forKey: characteristic.uuid) else { return }
        if let error = error {
            continuation.resume(throwing: AsyncBleClientError.operationFailed(.writeValue, error))
        } else {
            continuation.resume(returning: ())
        }
    }

    func handleDidUpdateNotificationState(for characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            if let continuation = notifyContinuations.removeValue(forKey: characteristic.uuid) {
                continuation.finish(throwing: AsyncBleClientError.operationFailed(.notifications, error))
            }
        }
    }

    // MARK: - Helper

    private func runWithTimeout<T>(_ timeout: TimeInterval?, _ operation: @escaping () async throws -> T) async throws -> T {
        if let timeout = timeout, timeout > 0 {
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { return try await operation() }
                group.addTask {
                    let nano = UInt64(timeout * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nano)
                    throw AsyncBleClientError.timeout
                }
                do {
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                } catch is CancellationError {
                    // operation task 因超时被 cancel 后抛出 CancellationError，映射为 .timeout
                    throw AsyncBleClientError.timeout
                }
            }
        } else {
            return try await operation()
        }
    }
}

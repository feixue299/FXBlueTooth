import Foundation
import CoreBluetooth

@available(iOS 13.0, macOS 10.15, *)
public final class AsyncPeripheralSession: NSObject, CBPeripheralDelegate {

    public let peripheral: CBPeripheral

    private var discoverServicesContinuation: CheckedContinuation<[CBService], Error>?
    private var discoverCharacteristicsContinuations: [CBUUID: CheckedContinuation<[CBCharacteristic], Error>] = [:]
    private var readContinuations: [CBUUID: CheckedContinuation<Data, Error>] = [:]
    private var writeContinuations: [CBUUID: CheckedContinuation<Void, Error>] = [:]
    private var notifyContinuations: [CBUUID: AsyncThrowingStream<Data, Error>.Continuation] = [:]

    public init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        self.peripheral.delegate = self
    }

    public func discoverServices(_ serviceUUIDs: [CBUUID]? = nil) async throws -> [CBService] {
        guard discoverServicesContinuation == nil else {
            throw AsyncBleClientError.busy
        }

        return try await withCheckedThrowingContinuation { continuation in
            discoverServicesContinuation = continuation
            peripheral.discoverServices(serviceUUIDs)
        }
    }

    public func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]? = nil, for service: CBService) async throws -> [CBCharacteristic] {
        if discoverCharacteristicsContinuations[service.uuid] != nil {
            throw AsyncBleClientError.busy
        }

        return try await withCheckedThrowingContinuation { continuation in
            discoverCharacteristicsContinuations[service.uuid] = continuation
            peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
        }
    }

    public func write(_ data: Data,
                      to characteristic: CBCharacteristic,
                      type: CBCharacteristicWriteType = .withResponse) async throws {
        if type == .withoutResponse {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            return
        }

        if writeContinuations[characteristic.uuid] != nil {
            throw AsyncBleClientError.busy
        }

        try await withCheckedThrowingContinuation { continuation in
            writeContinuations[characteristic.uuid] = continuation
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }

    public func readValue(for characteristic: CBCharacteristic) async throws -> Data {
        if readContinuations[characteristic.uuid] != nil {
            throw AsyncBleClientError.busy
        }

        return try await withCheckedThrowingContinuation { continuation in
            readContinuations[characteristic.uuid] = continuation
            peripheral.readValue(for: characteristic)
        }
    }

    public func notifications(for characteristic: CBCharacteristic) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            notifyContinuations[characteristic.uuid] = continuation
            peripheral.setNotifyValue(true, for: characteristic)

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.notifyContinuations.removeValue(forKey: characteristic.uuid)
                    self?.peripheral.setNotifyValue(false, for: characteristic)
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let continuation = discoverServicesContinuation else { return }
        discoverServicesContinuation = nil

        if let error = error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: peripheral.services ?? [])
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let continuation = discoverCharacteristicsContinuations.removeValue(forKey: service.uuid) else { return }

        if let error = error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: service.characteristics ?? [])
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let continuation = writeContinuations.removeValue(forKey: characteristic.uuid) else { return }

        if let error = error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: ())
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let continuation = readContinuations.removeValue(forKey: characteristic.uuid) {
            if let error = error {
                continuation.resume(throwing: error)
            } else if let data = characteristic.value {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: AsyncBleClientError.invalidState("Characteristic value is nil"))
            }
            return
        }

        guard let notifyContinuation = notifyContinuations[characteristic.uuid] else { return }

        if let error = error {
            notifyContinuation.finish(throwing: error)
            notifyContinuations.removeValue(forKey: characteristic.uuid)
        } else if let data = characteristic.value {
            notifyContinuation.yield(data)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let continuation = notifyContinuations[characteristic.uuid], let error = error else { return }
        continuation.finish(throwing: error)
        notifyContinuations.removeValue(forKey: characteristic.uuid)
    }
}

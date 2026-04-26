import Foundation
import CoreBluetooth

@available(iOS 13.0, macOS 10.15, *)
public final class AsyncBleManager: NSObject, CBCentralManagerDelegate {

    private var central: CBCentralManager!
    private var stateWaiters: [CheckedContinuation<Void, Error>] = []

    private var scanContinuation: AsyncThrowingStream<AsyncDiscoveredPeripheral, Error>.Continuation?
    private var scanMatcher: ((AsyncDiscoveredPeripheral) -> Bool)?

    private var pendingConnectContinuation: CheckedContinuation<CBPeripheral, Error>?
    private var pendingConnectRequest: AsyncConnectRequest?

    private var waitingDisconnectIdentifier: UUID?
    private var pendingDisconnectContinuation: CheckedContinuation<Void, Error>?

    private var connectTimeoutTask: Task<Void, Never>?

    private var eventContinuation: AsyncStream<AsyncConnectionEvent>.Continuation?

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    public init(options: [String: Any]? = nil) {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: options)
    }

    public func connectionEvents() -> AsyncStream<AsyncConnectionEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    self?.eventContinuation = nil
                }
            }
        }
    }

    public func scan(_ request: AsyncScanRequest = AsyncScanRequest()) -> AsyncThrowingStream<AsyncDiscoveredPeripheral, Error> {
        AsyncThrowingStream { continuation in
            self.scanContinuation = continuation
            self.scanMatcher = request.matcher

            Task {
                do {
                    try await self.ensurePoweredOn()
                    self.central.scanForPeripherals(withServices: request.serviceUUIDs, options: request.options)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [weak self] _ in
                Task {
                    self?.stopScan()
                }
            }
        }
    }

    public func connect(_ request: AsyncConnectRequest) async throws -> CBPeripheral {
        guard pendingConnectContinuation == nil else {
            throw AsyncBleClientError.busy
        }

        try await ensurePoweredOn()

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingConnectContinuation = continuation
            self.pendingConnectRequest = request

            switch request.target {
            case .peripheral(let peripheral):
                self.startConnect(peripheral, options: request.connectOptions, timeout: request.timeout)
            case .identifier(let identifier):
                if let peripheral = self.central.retrievePeripherals(withIdentifiers: [identifier]).first {
                    self.startConnect(peripheral, options: request.connectOptions, timeout: request.timeout)
                } else {
                    self.central.scanForPeripherals(withServices: request.scanServiceUUIDs, options: request.scanOptions)
                    self.scheduleConnectTimeout(request.timeout)
                }
            case .matcher:
                self.central.scanForPeripherals(withServices: request.scanServiceUUIDs, options: request.scanOptions)
                self.scheduleConnectTimeout(request.timeout)
            }
        }
    }

    public func disconnect(_ peripheral: CBPeripheral) async throws {
        try await ensurePoweredOn()
        guard pendingDisconnectContinuation == nil else {
            throw AsyncBleClientError.busy
        }

        try await withCheckedThrowingContinuation { continuation in
            self.waitingDisconnectIdentifier = peripheral.identifier
            self.pendingDisconnectContinuation = continuation
            self.central.cancelPeripheralConnection(peripheral)
        }
    }

    public func stopScan() {
        central.stopScan()
        scanContinuation = nil
        scanMatcher = nil
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            stateWaiters.forEach { $0.resume(returning: ()) }
            stateWaiters.removeAll()
        default:
            let error = AsyncBleClientError.bluetoothUnavailable(central.state)
            stateWaiters.forEach { $0.resume(throwing: error) }
            stateWaiters.removeAll()
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any],
                               rssi RSSI: NSNumber) {
        let discovered = AsyncDiscoveredPeripheral(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)

        if let scanContinuation = scanContinuation {
            if let matcher = scanMatcher {
                if matcher(discovered) {
                    scanContinuation.yield(discovered)
                }
            } else {
                scanContinuation.yield(discovered)
            }
        }

        guard let request = pendingConnectRequest else { return }
        switch request.target {
        case .identifier(let identifier):
            if peripheral.identifier == identifier {
                startConnect(peripheral, options: request.connectOptions, timeout: request.timeout)
            }
        case .matcher(let matcher):
            if matcher(discovered) {
                startConnect(peripheral, options: request.connectOptions, timeout: request.timeout)
            }
        case .peripheral:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        clearConnectTimeout()
        central.stopScan()
        pendingConnectRequest = nil

        pendingConnectContinuation?.resume(returning: peripheral)
        pendingConnectContinuation = nil

        eventContinuation?.yield(.connected(peripheral))
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        clearConnectTimeout()
        central.stopScan()
        pendingConnectRequest = nil

        pendingConnectContinuation?.resume(throwing: AsyncBleClientError.connectFailed(peripheral, error))
        pendingConnectContinuation = nil
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        eventContinuation?.yield(.disconnected(peripheral, error))

        guard waitingDisconnectIdentifier == peripheral.identifier else { return }

        waitingDisconnectIdentifier = nil
        if let error = error {
            pendingDisconnectContinuation?.resume(throwing: error)
        } else {
            pendingDisconnectContinuation?.resume(returning: ())
        }
        pendingDisconnectContinuation = nil
    }

    private func ensurePoweredOn() async throws {
        if central.state == .poweredOn { return }

        try await withCheckedThrowingContinuation { continuation in
            if central.state == .poweredOn {
                continuation.resume(returning: ())
            } else {
                stateWaiters.append(continuation)
            }
        }
    }

    private func startConnect(_ peripheral: CBPeripheral, options: [String: Any]?, timeout: TimeInterval) {
        clearConnectTimeout()
        central.stopScan()
        central.connect(peripheral, options: options)
        scheduleConnectTimeout(timeout)
    }

    private func scheduleConnectTimeout(_ timeout: TimeInterval) {
        clearConnectTimeout()
        connectTimeoutTask = Task {
            if timeout > 0 {
                let nano = UInt64(timeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nano)
            }

            guard let continuation = pendingConnectContinuation else { return }

            central.stopScan()
            pendingConnectRequest = nil
            pendingConnectContinuation = nil
            continuation.resume(throwing: AsyncBleClientError.timeout)
        }
    }

    private func clearConnectTimeout() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
    }
}

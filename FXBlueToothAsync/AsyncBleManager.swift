import Foundation
import CoreBluetooth

@available(iOS 13.0, macOS 10.15, *)
public final class AsyncBleManager: NSObject, CBCentralManagerDelegate {

    private var central: CBCentralManager!
    private var stateWaiters: [CheckedContinuation<Void, Error>] = []

    private var scanContinuation: AsyncThrowingStream<AsyncDiscoveredPeripheral, Error>.Continuation?

    private var pendingConnectContinuation: CheckedContinuation<AsyncConnectedPeripheral, Error>?
    private var pendingConnectPeripheral: CBPeripheral?
    private var pendingConnectTimeout: Task<Void, Never>?

    private var waitingDisconnectIdentifier: UUID?
    private var pendingDisconnectContinuation: CheckedContinuation<Void, Error>?

    private var eventContinuation: AsyncStream<AsyncConnectionEvent>.Continuation?

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    public init(options: [String: Any]? = nil) {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: options)
    }

    // MARK: - State

    /// 获取蓝牙状态
    public func getState() async throws -> CBManagerState {
        try await ensurePoweredOn()
        return central.state
    }

    // MARK: - Scan

    /// 扫描设备
    /// 
    /// 使用示例:
    /// ```
    /// let stream = manager.scan(AsyncScanRequest())
    /// for try await discovered in stream {
    ///     print("Found: \(discovered.peripheral.name ?? "Unknown")")
    /// }
    /// ```
    public func scan(
        _ request: AsyncScanRequest = AsyncScanRequest()
    ) -> AsyncThrowingStream<AsyncDiscoveredPeripheral, Error> {
        AsyncThrowingStream { continuation in
            self.scanContinuation = continuation

            Task {
                do {
                    try await self.ensurePoweredOn()
                    self.central.scanForPeripherals(
                        withServices: request.serviceUUIDs,
                        options: request.options
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [weak self] _ in
                Task {
                    self?.central.stopScan()
                    self?.scanContinuation = nil
                }
            }
        }
    }

    // MARK: - Connect

    /// 连接到发现的设备
    /// - Parameters:
    ///   - discovered: 扫描时发现的设备
    ///   - timeout: 连接超时时间，默认15秒
    /// - Returns: 已连接的设备对象
    public func connect(
        _ discovered: AsyncDiscoveredPeripheral,
        timeout: TimeInterval = 15
    ) async throws -> AsyncConnectedPeripheral {
        return try await connect(discovered.peripheral, timeout: timeout)
    }

    /// 连接到指定的peripheral
    public func connect(
        _ peripheral: CBPeripheral,
        timeout: TimeInterval = 15
    ) async throws -> AsyncConnectedPeripheral {
        guard pendingConnectContinuation == nil else {
            throw AsyncBleClientError.busy
        }

        return try await withTaskCancellationHandler(operation: {
            try await ensurePoweredOn()

            return try await withCheckedThrowingContinuation { continuation in
                self.pendingConnectContinuation = continuation
                self.pendingConnectPeripheral = peripheral

                self.central.stopScan()
                self.central.connect(peripheral, options: nil)
                self.scheduleConnectTimeout(timeout)
            }
        }, onCancel: {
            Task {
                self.pauseConnectForTaskCancellation()
            }
        })
    }

    // MARK: - Disconnect

    /// 断开设备连接
    public func disconnect(_ peripheral: CBPeripheral) async throws {
        try await ensurePoweredOn()
        guard pendingDisconnectContinuation == nil else {
            throw AsyncBleClientError.busy
        }

        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.waitingDisconnectIdentifier = peripheral.identifier
                self.pendingDisconnectContinuation = continuation
                self.central.cancelPeripheralConnection(peripheral)
            }
        }, onCancel: {
            Task {
                self.pauseDisconnectForTaskCancellation()
            }
        })
    }

    // MARK: - Events

    /// 获取连接事件流 (已连接/已断开)
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

    /// 停止扫描
    public func stopScan() {
        central.stopScan()
    }

    // MARK: - CBCentralManagerDelegate

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

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let discovered = AsyncDiscoveredPeripheral(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
        scanContinuation?.yield(discovered)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        clearConnectTimeout()
        central.stopScan()
        pendingConnectPeripheral = nil

        let connectedPeripheral = AsyncConnectedPeripheral(peripheral: peripheral)
        pendingConnectContinuation?.resume(returning: connectedPeripheral)
        pendingConnectContinuation = nil

        eventContinuation?.yield(.connected(peripheral))
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        clearConnectTimeout()
        central.stopScan()
        pendingConnectPeripheral = nil

        let error = error ?? NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connect failed"])
        pendingConnectContinuation?.resume(throwing: AsyncBleClientError.connectFailed(peripheral, error))
        pendingConnectContinuation = nil
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        eventContinuation?.yield(.disconnected(peripheral, error))

        guard waitingDisconnectIdentifier == peripheral.identifier else { return }

        waitingDisconnectIdentifier = nil
        if let error = error {
            pendingDisconnectContinuation?.resume(throwing: AsyncBleClientError.operationFailed(.disconnect, error))
        } else {
            pendingDisconnectContinuation?.resume(returning: ())
        }
        pendingDisconnectContinuation = nil
    }

    // MARK: - Private Helpers

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

    private func scheduleConnectTimeout(_ timeout: TimeInterval) {
        clearConnectTimeout()
        pendingConnectTimeout = Task {
            if timeout > 0 {
                let nano = UInt64(timeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nano)
            }

            guard self.pendingConnectContinuation != nil else { return }

            self.central.stopScan()
            self.pendingConnectPeripheral = nil
            self.pendingConnectContinuation?.resume(throwing: AsyncBleClientError.timeout)
            self.pendingConnectContinuation = nil
        }
    }

    private func clearConnectTimeout() {
        pendingConnectTimeout?.cancel()
        pendingConnectTimeout = nil
    }

    private func pauseConnectForTaskCancellation() {
        clearConnectTimeout()
        central.stopScan()
        if let peripheral = pendingConnectPeripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        pendingConnectPeripheral = nil
        pendingConnectContinuation = nil
    }

    private func pauseDisconnectForTaskCancellation() {
        waitingDisconnectIdentifier = nil
        pendingDisconnectContinuation = nil
    }
}

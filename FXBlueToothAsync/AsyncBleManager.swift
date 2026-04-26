import Foundation
import CoreBluetooth

@available(iOS 13.0, macOS 10.15, *)
public final class AsyncBleManager: NSObject, CBCentralManagerDelegate {

    private var central: CBCentralManager!
    private var stateWaiters: [CheckedContinuation<Void, Error>] = []

    private var scanContinuation: CheckedContinuation<AsyncPeripheral, Error>?
    private var scanHandler: ((_ discovered: AsyncDiscoveredPeripheral) async throws -> ScanAction)?

    private var pendingConnectContinuation: CheckedContinuation<AsyncPeripheral, Error>?
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

    // MARK: - Scan & Connect

    /// 扫描设备，在闭包中处理每个发现的设备
    /// 闭包返回 ScanAction：
    /// - .skip：跳过，继续扫描
    /// - .connect：连接该设备，停止扫描并返回已连接的设备
    ///
    /// 使用示例:
    /// ```
    /// let device = try await manager.scan(request) { discovered in
    ///     if discovered.peripheral.name == "MyDevice" {
    ///         return .connect  // 连接这个设备
    ///     }
    ///     return .skip  // 继续扫描
    /// }
    /// ```
    public func scan(
        _ request: AsyncScanRequest = AsyncScanRequest(),
        onDiscovered: @escaping (AsyncDiscoveredPeripheral) async throws -> ScanAction
    ) async throws -> AsyncPeripheral {
        try await ensurePoweredOn()

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.scanContinuation = continuation
                self.scanHandler = onDiscovered

                self.central.scanForPeripherals(
                    withServices: request.serviceUUIDs,
                    options: request.options
                )
            }
        }, onCancel: {
            Task {
                self.central.stopScan()
                self.scanContinuation = nil
                self.scanHandler = nil
            }
        })
    }

    /// 从扫描中连接设备（在 scan 的闭包中调用）
    /// 成功连接会停止扫描并返回已连接的设备
    public func connect(_ discovered: AsyncDiscoveredPeripheral, timeout: TimeInterval = 15) async throws -> AsyncPeripheral {
        guard pendingConnectContinuation == nil else {
            throw AsyncBleClientError.busy
        }

        return try await withTaskCancellationHandler(operation: {
            try await ensurePoweredOn()

            return try await withCheckedThrowingContinuation { continuation in
                self.pendingConnectContinuation = continuation
                self.pendingConnectPeripheral = discovered.peripheral

                self.central.stopScan()
                self.central.connect(discovered.peripheral, options: nil)
                self.scheduleConnectTimeout(timeout)
            }
        }, onCancel: {
            Task {
                self.pauseConnectForTaskCancellation()
            }
        })
    }

    /// 直接连接到指定的 peripheral
    public func connect(_ peripheral: CBPeripheral, timeout: TimeInterval = 15) async throws -> AsyncPeripheral {
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

    /// 断开连接
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

    /// 获取连接事件流
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
        scanHandler = nil
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

        Task {
            do {
                let action = try await scanHandler?(discovered) ?? .skip
                
                switch action {
                case .skip:
                    // 继续扫描，不做任何操作
                    break
                case .connect:
                    // 连接该设备
                    central.stopScan()
                    do {
                        let connectedPeripheral = try await self.connectDirectly(peripheral, timeout: 15)
                        self.scanContinuation?.resume(returning: connectedPeripheral)
                        self.scanContinuation = nil
                        self.scanHandler = nil
                    } catch {
                        self.scanContinuation?.resume(throwing: error)
                        self.scanContinuation = nil
                        self.scanHandler = nil
                    }
                }
            } catch {
                // 闭包错误，继续扫描
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        clearConnectTimeout()
        central.stopScan()
        pendingConnectPeripheral = nil

        let connectedPeripheral = AsyncPeripheral(peripheral: peripheral)
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

    /// 内部连接方法，用于 scan 中的连接（不检查 busy）
    private func connectDirectly(_ peripheral: CBPeripheral, timeout: TimeInterval = 15) async throws -> AsyncPeripheral {
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.pendingConnectContinuation = continuation
                self.pendingConnectPeripheral = peripheral

                self.central.connect(peripheral, options: nil)
                self.scheduleConnectTimeout(timeout)
            }
        }, onCancel: {
            Task {
                self.pauseConnectForTaskCancellation()
            }
        })
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
        scanHandler = nil
    }

    private func pauseDisconnectForTaskCancellation() {
        waitingDisconnectIdentifier = nil
        pendingDisconnectContinuation = nil
    }
}

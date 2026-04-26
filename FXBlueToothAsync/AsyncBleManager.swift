import Foundation
import CoreBluetooth

@available(iOS 13.0, macOS 10.15, *)
public final class AsyncBleManager: NSObject, CBCentralManagerDelegate {

    // 使用 protocol 类型，允许测试注入 MockCentralManager
    var central: any CentralManagerProtocol

    private var stateWaiters: [CheckedContinuation<Void, Error>] = []

    private var scanContinuation: CheckedContinuation<AsyncPeripheral, Error>?
    private var scanHandler: ((_ discovered: AsyncDiscoveredPeripheral) async throws -> ScanAction)?

    private var pendingConnectContinuation: CheckedContinuation<AsyncPeripheral, Error>?
    private var pendingConnectPeripheral: CBPeripheral?
    private var pendingConnectTimeout: Task<Void, Never>?

    private var waitingDisconnectIdentifier: UUID?
    private var pendingDisconnectContinuation: CheckedContinuation<Void, Error>?

    private var eventContinuation: AsyncStream<AsyncConnectionEvent>.Continuation?

    // MARK: - Init

    public override init() {
        let cm = CBCentralManager()
        self.central = cm
        super.init()
        cm.delegate = self
    }

    public init(options: [String: Any]? = nil) {
        let cm = CBCentralManager(delegate: nil, queue: nil, options: options)
        self.central = cm
        super.init()
        cm.delegate = self
    }

    /// 测试专用初始化，注入 MockCentralManager
    init(central: any CentralManagerProtocol) {
        self.central = central
        super.init()
    }

    // MARK: - State

    /// 获取蓝牙状态
    public func getState() async throws -> CBManagerState {
        try await ensurePoweredOn()
        return central.state
    }

    // MARK: - Scan & Connect

    /// 扫描设备，闭包返回 ScanAction 控制流程
    /// - `.skip`：跳过，继续扫描
    /// - `.connect`：连接该设备，停止扫描并返回已连接的设备
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
    public func disconnect(_ peripheral: any PeripheralProtocol) async throws {
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

    /// 获取连接/断开事件流
    public func connectionEvents() -> AsyncStream<AsyncConnectionEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { self?.eventContinuation = nil }
            }
        }
    }

    /// 停止扫描
    public func stopScan() {
        central.stopScan()
        scanHandler = nil
    }

    // MARK: - CBCentralManagerDelegate (转发到可测试的 handle 方法)

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleStateUpdate()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        handleDidDiscover(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        handleDidConnect(peripheral: peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        handleDidFailToConnect(peripheral: peripheral, error: error)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        handleDidDisconnect(peripheral: peripheral, error: error)
    }

    // MARK: - Internal Handlers（可在测试中直接调用）

    func handleStateUpdate() {
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

    func handleDidDiscover(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let discovered = AsyncDiscoveredPeripheral(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi)

        Task {
            do {
                let action = try await scanHandler?(discovered) ?? .skip

                switch action {
                case .skip:
                    break
                case .connect:
                    central.stopScan()
                    do {
                        let connectedPeripheral = try await connectDirectly(peripheral, timeout: 15)
                        scanContinuation?.resume(returning: connectedPeripheral)
                        scanContinuation = nil
                        scanHandler = nil
                    } catch {
                        scanContinuation?.resume(throwing: error)
                        scanContinuation = nil
                        scanHandler = nil
                    }
                }
            } catch {
                // 闭包错误，继续扫描
            }
        }
    }

    func handleDidConnect(peripheral: CBPeripheral) {
        clearConnectTimeout()
        central.stopScan()
        pendingConnectPeripheral = nil

        let connectedPeripheral = AsyncPeripheral(peripheral: peripheral)
        pendingConnectContinuation?.resume(returning: connectedPeripheral)
        pendingConnectContinuation = nil

        eventContinuation?.yield(.connected(peripheral))
    }

    func handleDidFailToConnect(peripheral: CBPeripheral, error: Error?) {
        clearConnectTimeout()
        central.stopScan()
        pendingConnectPeripheral = nil

        let err = error ?? NSError(domain: "BLE", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connect failed"])
        pendingConnectContinuation?.resume(throwing: AsyncBleClientError.connectFailed(peripheral, err))
        pendingConnectContinuation = nil
    }

    func handleDidDisconnect(peripheral: CBPeripheral, error: Error?) {
        eventContinuation?.yield(.disconnected(peripheral, error))
        resolveDisconnect(identifier: peripheral.identifier, error: error)
    }

    /// 测试专用：从 MockPeripheral 触发断开回调
    func handleDidDisconnect(peripheral: any PeripheralProtocol, error: Error?) {
        resolveDisconnect(identifier: peripheral.identifier, error: error)
    }

    private func resolveDisconnect(identifier: UUID, error: Error?) {
        guard waitingDisconnectIdentifier == identifier else { return }

        waitingDisconnectIdentifier = nil
        if let error = error {
            pendingDisconnectContinuation?.resume(throwing: AsyncBleClientError.operationFailed(.disconnect, error))
        } else {
            pendingDisconnectContinuation?.resume(returning: ())
        }
        pendingDisconnectContinuation = nil
    }

    // MARK: - Private Helpers

    private func connectDirectly(_ peripheral: CBPeripheral, timeout: TimeInterval = 15) async throws -> AsyncPeripheral {
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.pendingConnectContinuation = continuation
                self.pendingConnectPeripheral = peripheral

                self.central.connect(peripheral, options: nil)
                self.scheduleConnectTimeout(timeout)
            }
        }, onCancel: {
            Task { self.pauseConnectForTaskCancellation() }
        })
    }

    func ensurePoweredOn() async throws {
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

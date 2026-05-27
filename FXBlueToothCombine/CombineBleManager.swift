import Foundation
import Combine
import CoreBluetooth
@_exported import FXBlueToothCore

/// Combine 风格的 BLE 中央管理器
///
/// 设计要点：
/// - 所有公共 API 返回 `AnyPublisher`，可用 `flatMap` / `share` 等标准算子组合
/// - 一次性操作（connect / disconnect）订阅时触发底层调用，完成后自动 complete
/// - 扫描多订阅者共享一个 `scanForPeripherals` 会话，引用计数归零时 `stopScan`
@available(iOS 13.0, macOS 10.15, *)
public final class CombineBleManager {

    private let central: CentralManagerProtocol
    private let queue: DispatchQueue
    private let bridge: CentralDelegateBridge

    private let lock = NSLock()
    private var scanSubscribers = 0
    private var lastScanServices: [CBUUID]? = nil
    private var lastScanOptions: [String: Any]? = nil

    /// 当前已连接外设注册表，按 identifier 去重
    private var connectedRegistry: [UUID: CombinePeripheral] = [:]
    private let connectedSubject = CurrentValueSubject<[CombinePeripheral], Never>([])
    private var registryBag = Set<AnyCancellable>()

    public init(central: CentralManagerProtocol? = nil,
                queue: DispatchQueue = DispatchQueue(label: "FXBlueToothCombine.central")) {
        self.queue = queue
        self.central = central ?? CBCentralManager(delegate: nil, queue: queue)
        self.bridge = CentralDelegateBridge()
        self.bridge.manager = self
        self.central.centralDelegate = bridge
        wireConnectedRegistry()
    }

    private func wireConnectedRegistry() {
        bridge.didConnect
            .sink { [weak self] peripheral in
                self?.registerConnected(peripheral)
            }
            .store(in: &registryBag)

        bridge.didDisconnect
            .sink { [weak self] (peripheral, _) in
                self?.unregisterConnected(identifier: peripheral.identifier)
            }
            .store(in: &registryBag)
    }

    @discardableResult
    private func registerConnected(_ peripheral: any PeripheralProtocol) -> CombinePeripheral {
        lock.lock()
        if let existing = connectedRegistry[peripheral.identifier] {
            lock.unlock()
            return existing
        }
        let wrapped = CombinePeripheral(peripheral: peripheral, queue: queue)
        connectedRegistry[peripheral.identifier] = wrapped
        let snapshot = Array(connectedRegistry.values)
        lock.unlock()
        connectedSubject.send(snapshot)
        return wrapped
    }

    private func unregisterConnected(identifier: UUID) {
        lock.lock()
        guard connectedRegistry.removeValue(forKey: identifier) != nil else {
            lock.unlock()
            return
        }
        let snapshot = Array(connectedRegistry.values)
        lock.unlock()
        connectedSubject.send(snapshot)
    }

    var centralState: CBManagerState { central.state }

    // MARK: - State

    /// 粘性当前状态，订阅时立即拿到当前值
    public var state: AnyPublisher<CBManagerState, Never> {
        bridge.stateSubject.eraseToAnyPublisher()
    }

    /// 连接 / 断开事件总线，独立于具体的 connect 调用
    public var connectionEvents: AnyPublisher<ConnectionEvent, Never> {
        let connects = bridge.didConnect.map { ConnectionEvent.connected($0) }
        let disconnects = bridge.didDisconnect.map { ConnectionEvent.disconnected($0.0, $0.1) }
        return connects.merge(with: disconnects).eraseToAnyPublisher()
    }

    /// 当前所有已连接外设的快照流
    ///
    /// - 粘性：订阅时立刻拿到当前已连接列表
    /// - 自动维护：连接成功 → 加入；断开 → 移除
    /// - 同一 identifier 的外设全局唯一，与 `connect()` 返回的实例一致
    public var connectedPeripherals: AnyPublisher<[CombinePeripheral], Never> {
        connectedSubject.eraseToAnyPublisher()
    }

    /// 当前快照（非响应式访问，便于命令式查询）
    public var currentConnectedPeripherals: [CombinePeripheral] {
        lock.lock()
        defer { lock.unlock() }
        return Array(connectedRegistry.values)
    }

    // MARK: - Scan

    /// 扫描外设
    ///
    /// 多个订阅者共享一次底层扫描会话；最后一个订阅取消时调用 `stopScan`
    public func scan(services: [CBUUID]? = nil,
                     options: [String: Any]? = nil)
    -> AnyPublisher<DiscoveredPeripheral, BleError> {
        let bridge = self.bridge
        return Deferred { [weak self] () -> AnyPublisher<DiscoveredPeripheral, BleError> in
            guard let self = self else {
                return Empty<DiscoveredPeripheral, BleError>().eraseToAnyPublisher()
            }
            return bridge.didDiscover
                .setFailureType(to: BleError.self)
                .handleEvents(
                    receiveSubscription: { _ in self.beginScan(services: services, options: options) },
                    receiveCancel: { self.endScan() }
                )
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    private func beginScan(services: [CBUUID]?, options: [String: Any]?) {
        lock.lock()
        scanSubscribers += 1
        let shouldStart = scanSubscribers == 1
        lastScanServices = services
        lastScanOptions = options
        lock.unlock()
        if shouldStart {
            central.scanForPeripherals(withServices: services, options: options)
        }
    }

    private func endScan() {
        lock.lock()
        scanSubscribers = max(0, scanSubscribers - 1)
        let shouldStop = scanSubscribers == 0
        lock.unlock()
        if shouldStop {
            central.stopScan()
        }
    }

    // MARK: - Connect

    /// 连接外设：成功后发出一个 `CombinePeripheral` 并 complete；失败 / 超时发 failure
    public func connect(_ peripheral: CBPeripheral,
                        timeout: TimeInterval? = nil)
    -> AnyPublisher<CombinePeripheral, BleError> {
        let bridge = self.bridge
        let queue = self.queue
        let central = self.central
        let success = bridge.didConnect
            .filter { $0.identifier == peripheral.identifier }
            .map { [weak self] p -> CombinePeripheral in
                // 复用注册表内的实例（在 wireConnectedRegistry 中已加入），保证全局唯一
                self?.registerConnected(p)
                    ?? CombinePeripheral(peripheral: p, queue: queue)
            }
            .setFailureType(to: BleError.self)

        let failure = bridge.didFailToConnect
            .filter { $0.0.identifier == peripheral.identifier }
            .setFailureType(to: BleError.self)
            .tryMap { (p, e) -> CombinePeripheral in
                throw BleError.connectFailed(p, e)
            }
            .mapError { ($0 as? BleError) ?? .connectFailed(peripheral, $0) }

        let merged = success.merge(with: failure).first()
            .handleEvents(receiveSubscription: { _ in
                central.connect(peripheral, options: nil)
            })
        return Self.applyTimeout(merged.eraseToAnyPublisher(),
                                 timeout: timeout, op: .connect, queue: queue)
    }

    /// 断开外设
    public func disconnect(_ peripheral: CombinePeripheral,
                           timeout: TimeInterval? = nil)
    -> AnyPublisher<Void, BleError> {
        let bridge = self.bridge
        let central = self.central
        let target = peripheral.peripheral
        let done = bridge.didDisconnect
            .filter { $0.0.identifier == target.identifier }
            .map { _ in () }
            .setFailureType(to: BleError.self)
            .first()
            .handleEvents(receiveSubscription: { _ in
                central.cancelPeripheralConnection(target)
            })
        return Self.applyTimeout(done.eraseToAnyPublisher(),
                                 timeout: timeout, op: .disconnect, queue: queue)
    }

    // MARK: - Internal

    static func applyTimeout<T>(_ pub: AnyPublisher<T, BleError>,
                                timeout: TimeInterval?,
                                op: BleError.Operation,
                                queue: DispatchQueue) -> AnyPublisher<T, BleError> {
        guard let timeout = timeout else { return pub }
        return pub.timeout(.seconds(timeout), scheduler: queue,
                           customError: { BleError.timeout(op) })
            .eraseToAnyPublisher()
    }
}

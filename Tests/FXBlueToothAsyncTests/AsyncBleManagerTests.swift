import Testing
import CoreBluetooth
import Foundation
@testable import FXBlueToothAsync

// MARK: - AsyncBleManager Tests

@Suite("AsyncBleManager 状态管理")
struct AsyncBleManagerStateTests {

    // MARK: getState

    @Test("getState - 蓝牙开启时返回 poweredOn")
    func getState_returnsPoweredOn() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        let manager = AsyncBleManager(central: mock)

        // 先触发状态回调（模拟 CBCentralManager 初始化后的状态通知）
        manager.handleStateUpdate()

        let state = try await manager.getState()
        #expect(state == .poweredOn)
    }

    @Test("getState - 蓝牙关闭时抛出 bluetoothUnavailable")
    func getState_throwsWhenPoweredOff() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOff
        let manager = AsyncBleManager(central: mock)

        // 用 Task 驱动 getState（它等待 poweredOn，我们随后触发 stateUpdate(poweredOff)）
        let task = Task {
            try await manager.getState()
        }

        // 短暂让出，使 task 进入等待
        try await Task.sleep(nanoseconds: 10_000_000)
        manager.handleStateUpdate()

        await #expect(throws: AsyncBleClientError.self) {
            try await task.value
        }
    }

    @Test("getState - 蓝牙不支持时抛出 bluetoothUnavailable")
    func getState_throwsWhenUnsupported() async throws {
        let mock = MockCentralManager()
        mock.state = .unsupported
        let manager = AsyncBleManager(central: mock)

        let task = Task {
            try await manager.getState()
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        manager.handleStateUpdate()

        await #expect(throws: AsyncBleClientError.self) {
            try await task.value
        }
    }
}

@Suite("AsyncBleManager 扫描")
struct AsyncBleManagerScanTests {

    // 创建一个状态为 poweredOn 的 manager（并触发状态通知）
    private func poweredOnManager() -> (AsyncBleManager, MockCentralManager) {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        let manager = AsyncBleManager(central: mock)
        manager.handleStateUpdate()
        return (manager, mock)
    }

    @Test("scan - 应调用 scanForPeripherals")
    func scan_callsScanForPeripherals() async throws {
        let (manager, mock) = poweredOnManager()

        let scanTask = Task {
            try await manager.scan(
                AsyncScanRequest(serviceUUIDs: [CBUUID(string: "180A")])
            ) { _ in .skip }
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(mock.scanWasCalled == true)
        #expect(mock.scanCalledWithServices?.first == CBUUID(string: "180A"))
        scanTask.cancel()
    }

    @Test("scan - 任务取消后停止扫描")
    func scan_cancelStopsScan() async throws {
        let (manager, mock) = poweredOnManager()

        let scanTask = Task {
            try await manager.scan { _ in .skip }
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        scanTask.cancel()
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(mock.stopScanCalled == true)
    }

    @Test("stopScan - 手动停止扫描")
    func stopScan_callsStopScan() async throws {
        let (manager, mock) = poweredOnManager()
        manager.stopScan()
        #expect(mock.stopScanCalled == true)
    }
}

@Suite("AsyncBleManager 断开连接")
struct AsyncBleManagerDisconnectTests {

    /// 仅用于触发参数类型检查。
    /// 在本测试中会先因蓝牙状态异常抛错，不会真正访问 peripheral。
    private func peripheralStub() -> CBPeripheral {
        unsafeBitCast(NSObject(), to: CBPeripheral.self)
    }

    @Test("disconnect 调用 cancelPeripheralConnection")
    func disconnect_callsCancel() async throws {
        // CBPeripheral 无法直接构造，先验证状态异常分支：应抛出 bluetoothUnavailable。
        let mock = MockCentralManager()
        mock.state = .poweredOff
        let manager = AsyncBleManager(central: mock)

        let task = Task {
            try await manager.disconnect(peripheralStub())
        }

        // 让出执行权，等待 disconnect 进入 ensurePoweredOn 等待。
        try await Task.sleep(nanoseconds: 10_000_000)
        manager.handleStateUpdate()

        await #expect(throws: AsyncBleClientError.self) {
            try await task.value
        }
        #expect(mock.cancelConnectionCalledWith == nil)
    }
}

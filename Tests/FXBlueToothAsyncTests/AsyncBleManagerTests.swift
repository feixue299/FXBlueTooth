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
//        mock.state = .poweredOn
        let manager = AsyncBleManager(central: mock)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            mock.state = .poweredOn
        }

        let state = try await manager.getState()
        #expect(state == .poweredOn)
    }

    @Test("getState - 蓝牙关闭时抛出 bluetoothUnavailable")
    func getState_throwsWhenPoweredOff() async throws {
        let mock = MockCentralManager()
        mock.state = .unknown
        let manager = AsyncBleManager(central: mock)

        // 用 Task 驱动 getState（它等待 poweredOn，我们随后切到 poweredOff 触发状态回调）
        let task = Task {
            try await manager.getState()
        }

        // 短暂让出，使 task 进入等待
        try await Task.sleep(nanoseconds: 10_000_000)
        mock.state = .poweredOff

        await #expect(throws: AsyncBleClientError.self) {
            try await task.value
        }
    }

    @Test("getState - 蓝牙不支持时抛出 bluetoothUnavailable")
    func getState_throwsWhenUnsupported() async throws {
        let mock = MockCentralManager()
        mock.state = .unknown
        let manager = AsyncBleManager(central: mock)

        let task = Task {
            try await manager.getState()
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        mock.state = .unsupported

        await #expect(throws: AsyncBleClientError.self) {
            try await task.value
        }
    }
}

@Suite("AsyncBleManager 扫描")
struct AsyncBleManagerScanTests {

    private func fakePeripheral() -> CBPeripheral {
        unsafeBitCast(MockPeripheral(), to: CBPeripheral.self)
    }

    // 创建一个状态为 poweredOn 的 manager
    private func poweredOnManager() -> (AsyncBleManager, MockCentralManager) {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        let manager = AsyncBleManager(central: mock)
        return (manager, mock)
    }

    @Test("scan - 应调用 scanForPeripherals")
    func scan_callsScanForPeripherals() async throws {
        let (manager, mock) = poweredOnManager()
        mock.autoCallbackConnectResultOnConnect = true
        mock.autoCallbackDiscoveriesOnScan = true
        let peripheral = fakePeripheral()
        mock.discoveriesOnScan = [.init(peripheral: peripheral)]

        let scanTask = Task {
            try await manager.scan(
                AsyncScanRequest(serviceUUIDs: [CBUUID(string: "180A")])
            ) { _ in .connect }
        }

        _ = try await scanTask.value

        #expect(mock.scanWasCalled == true)
        #expect(mock.scanCalledWithServices?.first == CBUUID(string: "180A"))
        #expect(mock.eventLog == [
            "didUpdateState",
            "scanForPeripherals",
            "didDiscover",
            "stopScan",
            "connect",
            "didConnect",
            "stopScan"
        ])
    }

    @Test("scan - 任务取消后停止扫描")
    func scan_cancelStopsScan() async throws {
        let (manager, mock) = poweredOnManager()

        let scanTask = Task {
            try await manager.scan { _ in .skip }
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        scanTask.cancel()
        try await Task.sleep(nanoseconds: 10_000_000)

        await #expect(throws: (any Error).self) {
            try await scanTask.value
        }

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

    @Test("init(central:) - 会绑定 centralDelegate")
    func initWithCentral_bindsDelegate() async throws {
        let mock = MockCentralManager()
        let manager = AsyncBleManager(central: mock)

        #expect((mock.centralDelegate as AnyObject?) === (manager as AnyObject))
    }

    @Test("disconnect - 蓝牙关闭时抛出 bluetoothUnavailable")
    func disconnect_throwsWhenPoweredOff() async throws {
        let mock = MockCentralManager()
        mock.state = .unknown
        let manager = AsyncBleManager(central: mock)
        let peripheral = MockPeripheral()

        let task = Task {
            try await manager.disconnect(peripheral)
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        mock.state = .poweredOff

        await #expect(throws: AsyncBleClientError.self) {
            try await task.value
        }
        // 蓝牙不可用，不应调用 cancelPeripheralConnection
        #expect(mock.cancelConnectionCalledWithIdentifier == nil)
    }

    @Test("disconnect - 调用 cancelPeripheralConnection")
    func disconnect_callsCancelPeripheralConnection() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        mock.autoCallbackDisconnectOnCancel = true
        let manager = AsyncBleManager(central: mock)
        let peripheral = MockPeripheral()

        let task = Task {
            try await manager.disconnect(peripheral)
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        // 验证 cancelPeripheralConnection 已被调用
        #expect(mock.cancelConnectionCalledWithIdentifier == peripheral.identifier)
        try await task.value
        #expect(mock.eventLog.contains("cancelPeripheralConnection"))
        #expect(mock.eventLog.contains("didDisconnect"))
    }
}

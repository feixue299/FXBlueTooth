import Testing
import Combine
import CoreBluetooth
import Foundation
import FXBlueToothCore
@testable import FXBlueToothCombine

private func fakePeripheral() -> CBPeripheral {
    unsafeBitCast(MockPeripheral(), to: CBPeripheral.self)
}

@Suite("CombineBleManager - scan")
struct CombineBleManagerScanTests {

    @Test("scan - 订阅时调用 scanForPeripherals，取消时调用 stopScan")
    func scan_startStop() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        let manager = CombineBleManager(central: mock)
        var bag = Set<AnyCancellable>()

        manager.scan(services: [CBUUID(string: "180A")])
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &bag)

        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(mock.scanWasCalled == true)
        #expect(mock.scanCalledWithServices?.first == CBUUID(string: "180A"))

        bag.removeAll()
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(mock.stopScanCalled == true)
    }

    @Test("scan - 发现的外设通过 publisher 发出")
    func scan_emitsDiscoveries() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        let manager = CombineBleManager(central: mock)
        let peripheral = fakePeripheral()
        mock.autoCallbackDiscoveriesOnScan = true
        mock.discoveriesOnScan = [.init(peripheral: peripheral)]

        let received = await withCheckedContinuation { (cont: CheckedContinuation<DiscoveredPeripheral, Never>) in
            var bag = Set<AnyCancellable>()
            manager.scan()
                .first()
                .sink(receiveCompletion: { _ in _ = bag },
                      receiveValue: { cont.resume(returning: $0); bag.removeAll() })
                .store(in: &bag)
        }
        #expect(received.peripheral.identifier == peripheral.identifier)
    }

    @Test("scan - 多订阅者共享会话，最后一个取消才 stopScan")
    func scan_sharedSession() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        let manager = CombineBleManager(central: mock)

        var bag1 = Set<AnyCancellable>()
        var bag2 = Set<AnyCancellable>()

        manager.scan().sink(receiveCompletion: { _ in }, receiveValue: { _ in }).store(in: &bag1)
        manager.scan().sink(receiveCompletion: { _ in }, receiveValue: { _ in }).store(in: &bag2)

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(mock.eventLog.filter { $0 == "scan" }.count == 1)

        bag1.removeAll()
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(mock.stopScanCalled == false)

        bag2.removeAll()
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(mock.stopScanCalled == true)
    }
}

@Suite("CombineBleManager - connect / disconnect")
struct CombineBleManagerConnectTests {

    @Test("connect - 成功时发出 CombinePeripheral 并 complete")
    func connect_success() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        mock.autoCallbackConnectResultOnConnect = true
        let manager = CombineBleManager(central: mock)
        let peripheral = fakePeripheral()

        let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CombinePeripheral, Error>) in
            var bag = Set<AnyCancellable>()
            manager.connect(peripheral)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let e) = completion { cont.resume(throwing: e) }
                        _ = bag
                    },
                    receiveValue: { cont.resume(returning: $0); bag.removeAll() }
                )
                .store(in: &bag)
        }
        #expect(result.peripheral.identifier == peripheral.identifier)
        #expect(mock.connectCalledWith?.identifier == peripheral.identifier)
    }

    @Test("connect - 失败时发出 connectFailed 错误")
    func connect_failure() async throws {
        struct E: Error {}
        let mock = MockCentralManager()
        mock.state = .poweredOn
        mock.autoCallbackConnectResultOnConnect = true
        mock.connectErrorOnConnect = E()
        let manager = CombineBleManager(central: mock)
        let peripheral = fakePeripheral()

        await #expect(throws: BleError.self) {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CombinePeripheral, Error>) in
                var bag = Set<AnyCancellable>()
                manager.connect(peripheral)
                    .sink(
                        receiveCompletion: { completion in
                            if case .failure(let e) = completion { cont.resume(throwing: e) }
                            _ = bag
                        },
                        receiveValue: { _ in }
                    )
                    .store(in: &bag)
            }
        }
    }

    @Test("connect - 超时后发出 timeout 错误")
    func connect_timeout() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        // 不开启 autoCallbackConnectResultOnConnect → 永远不回调
        let manager = CombineBleManager(central: mock)
        let peripheral = fakePeripheral()

        await #expect(throws: BleError.self) {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CombinePeripheral, Error>) in
                var bag = Set<AnyCancellable>()
                manager.connect(peripheral, timeout: 0.05)
                    .sink(
                        receiveCompletion: { completion in
                            if case .failure(let e) = completion { cont.resume(throwing: e) }
                            _ = bag
                        },
                        receiveValue: { _ in }
                    )
                    .store(in: &bag)
            }
        }
    }

    @Test("connectedPeripherals - 连接后 sticky 流发出新列表，断开后移除")
    func connectedPeripherals_tracksLifecycle() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        mock.autoCallbackConnectResultOnConnect = true
        mock.autoCallbackDisconnectOnCancel = true
        let manager = CombineBleManager(central: mock)
        let peripheral = fakePeripheral()

        var snapshots: [[CombinePeripheral]] = []
        var bag = Set<AnyCancellable>()
        manager.connectedPeripherals
            .sink { snapshots.append($0) }
            .store(in: &bag)

        // 初始快照：空
        #expect(snapshots.first?.isEmpty == true)

        // 连接
        let cp = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CombinePeripheral, Error>) in
            var inner = Set<AnyCancellable>()
            manager.connect(peripheral)
                .sink(
                    receiveCompletion: { if case .failure(let e) = $0 { cont.resume(throwing: e) }; _ = inner },
                    receiveValue: { cont.resume(returning: $0); inner.removeAll() }
                )
                .store(in: &inner)
        }
        try await Task.sleep(nanoseconds: 5_000_000)

        #expect(snapshots.count >= 2)
        #expect(snapshots.last?.count == 1)
        #expect(snapshots.last?.first === cp)   // 与 connect() 返回的实例一致
        #expect(manager.currentConnectedPeripherals.count == 1)

        // 断开
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var inner = Set<AnyCancellable>()
            manager.disconnect(cp)
                .sink(
                    receiveCompletion: {
                        switch $0 {
                        case .finished: cont.resume()
                        case .failure(let e): cont.resume(throwing: e)
                        }
                        _ = inner
                    },
                    receiveValue: { _ in }
                )
                .store(in: &inner)
        }
        try await Task.sleep(nanoseconds: 5_000_000)

        #expect(snapshots.last?.isEmpty == true)
        #expect(manager.currentConnectedPeripherals.isEmpty)
    }

    @Test("connectedPeripherals - 新订阅者立刻拿到当前快照")
    func connectedPeripherals_sticky() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        mock.autoCallbackConnectResultOnConnect = true
        let manager = CombineBleManager(central: mock)
        let peripheral = fakePeripheral()

        _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CombinePeripheral, Error>) in
            var inner = Set<AnyCancellable>()
            manager.connect(peripheral)
                .sink(
                    receiveCompletion: { if case .failure(let e) = $0 { cont.resume(throwing: e) }; _ = inner },
                    receiveValue: { cont.resume(returning: $0); inner.removeAll() }
                )
                .store(in: &inner)
        }
        try await Task.sleep(nanoseconds: 5_000_000)

        // 之后才订阅，也能拿到当前列表
        let first = await withCheckedContinuation { (cont: CheckedContinuation<[CombinePeripheral], Never>) in
            var inner = Set<AnyCancellable>()
            manager.connectedPeripherals
                .first()
                .sink { cont.resume(returning: $0); inner.removeAll() }
                .store(in: &inner)
        }
        #expect(first.count == 1)
        #expect(first.first?.peripheral.identifier == peripheral.identifier)
    }

    @Test("disconnect - cancelPeripheralConnection 后发出完成")
    func disconnect_success() async throws {
        let mock = MockCentralManager()
        mock.state = .poweredOn
        mock.autoCallbackDisconnectOnCancel = true
        let manager = CombineBleManager(central: mock)
        let mockPeripheral = MockPeripheral()
        let cp = CombinePeripheral(peripheral: mockPeripheral)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var bag = Set<AnyCancellable>()
            manager.disconnect(cp)
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished: cont.resume()
                        case .failure(let e): cont.resume(throwing: e)
                        }
                        _ = bag
                    },
                    receiveValue: { _ in }
                )
                .store(in: &bag)
        }
        #expect(mock.cancelConnectionCalledWithIdentifier == mockPeripheral.identifier)
    }
}

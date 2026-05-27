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

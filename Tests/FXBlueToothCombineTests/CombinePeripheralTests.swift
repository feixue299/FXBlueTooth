import Testing
import Combine
import CoreBluetooth
import Foundation
import FXBlueToothCore
@testable import FXBlueToothCombine

@Suite("CombinePeripheral - discover")
struct CombinePeripheralDiscoverTests {

    @Test("discoverServices - 调用底层并发出 services 列表")
    func discoverServices_success() async throws {
        let mock = MockPeripheral()
        let service = CBMutableService(type: CBUUID(string: "180A"), primary: true)
        mock.services = [service]
        let cp = CombinePeripheral(peripheral: mock)

        let services = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CBService], Error>) in
            var bag = Set<AnyCancellable>()
            cp.discoverServices()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let e) = completion { cont.resume(throwing: e) }
                        _ = bag
                    },
                    receiveValue: { cont.resume(returning: $0); bag.removeAll() }
                )
                .store(in: &bag)
        }
        #expect(services.first?.uuid == CBUUID(string: "180A"))
    }

    @Test("discoverServices + discoverCharacteristics - flatMap 串联")
    func discover_chained() async throws {
        let mock = MockPeripheral()
        let service = CBMutableService(type: CBUUID(string: "180A"), primary: true)
        let ch = CBMutableCharacteristic(type: CBUUID(string: "2A29"),
                                          properties: [.read],
                                          value: nil,
                                          permissions: [.readable])
        service.characteristics = [ch]
        mock.services = [service]
        let cp = CombinePeripheral(peripheral: mock)

        let chars: [CBCharacteristic] = try await withCheckedThrowingContinuation { cont in
            var bag = Set<AnyCancellable>()
            cp.discoverServices()
                .flatMap { svcs -> AnyPublisher<[CBCharacteristic], BleError> in
                    cp.discoverCharacteristics(for: svcs.first!)
                }
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let e) = completion { cont.resume(throwing: e) }
                        _ = bag
                    },
                    receiveValue: { cont.resume(returning: $0); bag.removeAll() }
                )
                .store(in: &bag)
        }
        #expect(chars.first?.uuid == CBUUID(string: "2A29"))
    }
}

@Suite("CombinePeripheral - read / write")
struct CombinePeripheralIOTests {

    private func makeCharacteristic(_ uuid: String = "2A29",
                                    props: CBCharacteristicProperties = [.read, .write, .notify]) -> CBMutableCharacteristic {
        CBMutableCharacteristic(type: CBUUID(string: uuid),
                                properties: props, value: nil, permissions: [.readable, .writeable])
    }

    @Test("writeWithResponse - 等待 didWriteValueFor 后完成")
    func write_withResponse() async throws {
        let mock = MockPeripheral()
        let cp = CombinePeripheral(peripheral: mock)
        let ch = makeCharacteristic()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var bag = Set<AnyCancellable>()
            cp.writeWithResponse(Data([0x01]), to: ch)
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
        #expect(mock.writeValueCalledFor == ch.uuid)
        #expect(mock.writeValueTypeCalledWith == .withResponse)
    }

    @Test("writeWithResponse - 超时报错")
    func write_withResponseTimeout() async throws {
        let mock = MockPeripheral()
        mock.autoCallbackWriteValue = false
        let cp = CombinePeripheral(peripheral: mock)
        let ch = makeCharacteristic()

        await #expect(throws: BleError.self) {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                var bag = Set<AnyCancellable>()
                cp.writeWithResponse(Data([0x01]), to: ch, timeout: 0.05)
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
        }
    }

    @Test("writeWithoutResponse - 立即完成且类型为 withoutResponse")
    func write_withoutResponse() async throws {
        let mock = MockPeripheral()
        let cp = CombinePeripheral(peripheral: mock)
        let ch = makeCharacteristic()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var bag = Set<AnyCancellable>()
            cp.writeWithoutResponse(Data([0x02]), to: ch)
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
        #expect(mock.writeValueCalledFor == ch.uuid)
        #expect(mock.writeValueTypeCalledWith == .withoutResponse)
    }
}

@Suite("CombinePeripheral - notifications")
struct CombinePeripheralNotifyTests {

    @Test("notifications - 订阅时 setNotifyValue(true)，取消时 setNotifyValue(false)")
    func notify_subscribeUnsubscribe() async throws {
        let mock = MockPeripheral()
        let cp = CombinePeripheral(peripheral: mock)
        let ch = CBMutableCharacteristic(type: CBUUID(string: "2A37"),
                                          properties: [.notify], value: nil, permissions: [])
        var bag = Set<AnyCancellable>()

        cp.notifications(for: ch)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &bag)
        try await Task.sleep(nanoseconds: 5_000_000)
        #expect(mock.setNotifyLog.contains(where: { $0.0 == ch.uuid && $0.1 == true }))

        bag.removeAll()
        try await Task.sleep(nanoseconds: 5_000_000)
        #expect(mock.setNotifyLog.contains(where: { $0.0 == ch.uuid && $0.1 == false }))
    }

    @Test("notifications - 收到 didUpdateValueFor 后发出数据")
    func notify_receivesValues() async throws {
        let mock = MockPeripheral()
        let cp = CombinePeripheral(peripheral: mock)
        let ch = CBMutableCharacteristic(type: CBUUID(string: "2A37"),
                                          properties: [.notify], value: nil, permissions: [])

        let received = await withCheckedContinuation { (cont: CheckedContinuation<Data, Never>) in
            var bag = Set<AnyCancellable>()
            cp.notifications(for: ch)
                .first()
                .sink(receiveCompletion: { _ in _ = bag },
                      receiveValue: { cont.resume(returning: $0); bag.removeAll() })
                .store(in: &bag)

            Task {
                try? await Task.sleep(nanoseconds: 10_000_000)
                mock.push(notification: Data([0xAB]), for: ch)
            }
        }
        #expect(received == Data([0xAB]))
    }

    @Test("notifications - 两个独立订阅者各自 setNotifyValue")
    func notify_independentSubscribers() async throws {
        let mock = MockPeripheral()
        let cp = CombinePeripheral(peripheral: mock)
        let ch = CBMutableCharacteristic(type: CBUUID(string: "2A37"),
                                          properties: [.notify], value: nil, permissions: [])
        var bag1 = Set<AnyCancellable>()
        var bag2 = Set<AnyCancellable>()

        cp.notifications(for: ch).sink(receiveCompletion: { _ in }, receiveValue: { _ in }).store(in: &bag1)
        cp.notifications(for: ch).sink(receiveCompletion: { _ in }, receiveValue: { _ in }).store(in: &bag2)

        try await Task.sleep(nanoseconds: 5_000_000)
        let enables = mock.setNotifyLog.filter { $0.1 == true }.count
        #expect(enables == 2)
    }
}

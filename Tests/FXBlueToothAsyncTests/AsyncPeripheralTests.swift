import Testing
import CoreBluetooth
import Foundation
@testable import FXBlueToothAsync

@Suite("AsyncPeripheral 服务发现")
struct AsyncPeripheralDiscoverServicesTests {
    private func makePeripheral() -> (AsyncPeripheral, MockPeripheral) {
        let mock = MockPeripheral()
        return (AsyncPeripheral(peripheral: mock), mock)
    }

    @Test("discoverServices - 成功返回 services")
    func discoverServices_returnsServices() async throws {
        let (ap, mock) = makePeripheral()
        let uuid = CBUUID(string: "180A")
        mock.services = [CBMutableService(type: uuid, primary: true)]

        let services = try await ap.discover(serviceUUIDs: nil)
        #expect(services.count == 1)
        #expect(services.first?.uuid == uuid)
    }

    @Test("discoverServices - 错误时抛出异常")
    func discoverServices_throwsOnError() async throws {
        let (ap, mock) = makePeripheral()
        mock.discoverServicesError = NSError(domain: "BLE", code: 1)

        await #expect {
            try await ap.discover(serviceUUIDs: nil)
        } throws: { $0 is AsyncBleClientError }
    }

    @Test("discoverServices - 重复调用时抛出 busy")
    func discoverServices_throwsBusy() async throws {
        let (ap, mock) = makePeripheral()
        mock.autoCallbackDiscoverServices = false
        let task1 = Task { try await ap.discover(serviceUUIDs: nil) }

        try await Task.sleep(nanoseconds: 10_000_000)
        await #expect {
            try await ap.discover(serviceUUIDs: nil)
        } throws: { error in
            if case .busy = error as? AsyncBleClientError { return true }
            return false
        }

        task1.cancel()
        _ = try? await task1.value
    }

    @Test("discoverServices - 超时时抛出 timeout")
    func discoverServices_timeout() async throws {
        let (ap, mock) = makePeripheral()
        mock.autoCallbackDiscoverServices = false
        await #expect {
            try await ap.discover(serviceUUIDs: nil, timeout: 0.05)
        } throws: { error in
            if case .timeout = error as? AsyncBleClientError { return true }
            return false
        }
    }
}

@Suite("AsyncPeripheral Characteristic 发现")
struct AsyncPeripheralDiscoverCharacteristicsTests {
    private func makeSetup() -> (AsyncPeripheral, MockPeripheral, CBMutableService) {
        let mock = MockPeripheral()
        let ap = AsyncPeripheral(peripheral: mock)
        let service = CBMutableService(type: CBUUID(string: "180A"), primary: true)
        let char = CBMutableCharacteristic(
            type: CBUUID(string: "2A29"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        service.characteristics = [char]
        return (ap, mock, service)
    }

    @Test("discoverCharacteristics - 成功返回")
    func returnsCharacteristics() async throws {
        let (ap, _, service) = makeSetup()
        let chars = try await ap.discover(characteristicUUIDs: nil, for: service)
        #expect(chars.count == 1)
        #expect(chars.first?.uuid == CBUUID(string: "2A29"))
    }

    @Test("discoverCharacteristics - 错误时抛出异常")
    func throwsOnError() async throws {
        let (ap, mock, service) = makeSetup()
        mock.discoverCharacteristicsError = NSError(domain: "BLE", code: 2)

        await #expect {
            try await ap.discover(characteristicUUIDs: nil, for: service)
        } throws: { $0 is AsyncBleClientError }
    }

    @Test("discoverCharacteristics - 超时")
    func timeout() async throws {
        let (ap, mock, service) = makeSetup()
        mock.autoCallbackDiscoverCharacteristics = false
        await #expect {
            try await ap.discover(characteristicUUIDs: nil, for: service, timeout: 0.05)
        } throws: { error in
            if case .timeout = error as? AsyncBleClientError { return true }
            return false
        }
    }
}

@Suite("AsyncPeripheral 读写")
struct AsyncPeripheralReadWriteTests {
    private func makeSetup() -> (AsyncPeripheral, MockPeripheral, CBMutableCharacteristic) {
        let mock = MockPeripheral()
        let ap = AsyncPeripheral(peripheral: mock)
        let char = CBMutableCharacteristic(
            type: CBUUID(string: "2A29"),
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        return (ap, mock, char)
    }

    @Test("read - 成功返回数据")
    func read_returnsData() async throws {
        let (ap, mock, char) = makeSetup()
        let expected = Data([0x01, 0x02, 0x03])
        mock.readValueResultByUUID[char.uuid] = .success(expected)

        let data = try await ap.read(for: char)
        #expect(data == expected)
    }

    @Test("write withoutResponse - 立即完成")
    func write_withoutResponse() async throws {
        let (ap, mock, char) = makeSetup()
        try await ap.write(Data([0xFF]), to: char, type: .withoutResponse)
        #expect(mock.writeValueCalledFor == char.uuid)
    }

    @Test("write withResponse - 成功时返回")
    func write_withResponse_success() async throws {
        let (ap, _, char) = makeSetup()
        try await ap.write(Data([0xAB]), to: char, type: .withResponse)
    }
}

@Suite("AsyncPeripheral 通知")
struct AsyncPeripheralNotificationTests {
    @Test("notifications - 接收多次数据")
    func notifications_receivesValues() async throws {
        let mock = MockPeripheral()
        mock.autoCallbackNotificationsOnSubscribe = true
        let ap = AsyncPeripheral(peripheral: mock)
        let char = CBMutableCharacteristic(
            type: CBUUID(string: "2A29"),
            properties: [.notify],
            value: nil,
            permissions: []
        )
        mock.notificationValuesByUUID[char.uuid] = [Data([0x01]), Data([0x02]), Data([0x03])]

        let stream = ap.notifications(for: char)
        #expect(mock.setNotifyCalledFor == char.uuid)
        #expect(mock.setNotifyEnabled == true)

        var received: [Data] = []
        let task = Task {
            for try await data in stream {
                received.append(data)
                if received.count >= 3 { break }
            }
        }

        try await task.value
        #expect(received.count == 3)
    }
}

import Foundation
import CoreBluetooth
@testable import FXBlueToothAsync

/// 测试用 MockCentralManager，实现 CentralManagerProtocol
@available(iOS 13.0, macOS 10.15, *)
final class MockCentralManager: CentralManagerProtocol {

    private final class CallbackCentralCarrier: NSObject {}

    enum ConnectionPhase {
        case idle
        case scanning
        case connecting
        case connected
    }

    struct ScanDiscoveryEvent {
        let peripheral: CBPeripheral
        let advertisementData: [String: Any]
        let rssi: NSNumber
        let delayNanoseconds: UInt64

        init(
            peripheral: CBPeripheral,
            advertisementData: [String: Any] = [:],
            rssi: NSNumber = 0,
            delayNanoseconds: UInt64 = 5_000_000
        ) {
            self.peripheral = peripheral
            self.advertisementData = advertisementData
            self.rssi = rssi
            self.delayNanoseconds = delayNanoseconds
        }
    }

    // 可控制的状态
    var state: CBManagerState = .poweredOff {
        didSet {
            notifyStateUpdate()
        }
    }
    var centralDelegate: CBCentralManagerDelegate? = nil {
        didSet {
            // 模拟真实 central 在 delegate 就绪后回调一次当前状态
            notifyStateUpdate()
        }
    }

    // 调用记录
    var scanCalledWithServices: [CBUUID]? = nil
    var scanWasCalled = false
    var stopScanCalled = false
    var connectCalledWith: CBPeripheral? = nil
    var cancelConnectionCalledWithIdentifier: UUID? = nil

    // 回调顺序与状态
    var phase: ConnectionPhase = .idle
    var eventLog: [String] = []

    // 断开回调行为控制
    var autoCallbackDisconnectOnCancel: Bool = false
    var disconnectErrorOnCancel: Error? = nil
    var autoCallbackConnectResultOnConnect: Bool = false
    var connectErrorOnConnect: Error? = nil

    // 扫描行为控制
    var autoCallbackDiscoveriesOnScan: Bool = false
    var discoveriesOnScan: [ScanDiscoveryEvent] = []

    // 仅用于满足 delegate 回调签名中的 CBCentralManager 参数，避免测试时触发真实蓝牙权限检查。
    private lazy var callbackCentral = unsafeBitCast(CallbackCentralCarrier(), to: CBCentralManager.self)

    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {
        scanWasCalled = true
        scanCalledWithServices = serviceUUIDs
        phase = .scanning
        eventLog.append("scanForPeripherals")

        guard autoCallbackDiscoveriesOnScan else { return }
        for event in discoveriesOnScan {
            Task {
                try? await Task.sleep(nanoseconds: event.delayNanoseconds)
                self.notifyDidDiscover(
                    peripheral: event.peripheral,
                    advertisementData: event.advertisementData,
                    rssi: event.rssi
                )
            }
        }
    }

    func stopScan() {
        stopScanCalled = true
        eventLog.append("stopScan")
        if phase == .scanning {
            phase = .idle
        }
    }

    func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {
        connectCalledWith = peripheral
        phase = .connecting
        eventLog.append("connect")

        guard autoCallbackConnectResultOnConnect else { return }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            if let error = self.connectErrorOnConnect {
                self.notifyDidFailToConnect(peripheral: peripheral, error: error)
            } else {
                self.notifyDidConnect(peripheral: peripheral)
            }
        }
    }

    func cancelPeripheralConnection(_ peripheral: any PeripheralProtocol) {
        cancelConnectionCalledWithIdentifier = peripheral.identifier
        eventLog.append("cancelPeripheralConnection")
        guard autoCallbackDisconnectOnCancel else { return }

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            self.notifyDidDisconnect(peripheral: peripheral, error: self.disconnectErrorOnCancel)
        }
    }

    // MARK: - Delegate Notifications

    private func notifyStateUpdate() {
        guard let delegate = centralDelegate else { return }
        eventLog.append("didUpdateState")
        delegate.centralManagerDidUpdateState(callbackCentral)
    }

    private func notifyDidDiscover(
        peripheral: CBPeripheral,
        advertisementData: [String: Any] = [:],
        rssi: NSNumber = 0
    ) {
        guard let delegate = centralDelegate else { return }
        eventLog.append("didDiscover")
        delegate.centralManager?(
            callbackCentral,
            didDiscover: peripheral,
            advertisementData: advertisementData,
            rssi: rssi
        )
    }

    private func notifyDidConnect(peripheral: CBPeripheral) {
        guard let delegate = centralDelegate else { return }
        phase = .connected
        eventLog.append("didConnect")
        delegate.centralManager?(callbackCentral, didConnect: peripheral)
    }

    private func notifyDidFailToConnect(peripheral: CBPeripheral, error: Error?) {
        guard let delegate = centralDelegate else { return }
        phase = .idle
        eventLog.append("didFailToConnect")
        delegate.centralManager?(callbackCentral, didFailToConnect: peripheral, error: error)
    }

    private func notifyDidDisconnect(peripheral: any PeripheralProtocol, error: Error?) {
        phase = .idle
        eventLog.append("didDisconnect")

        if let cbPeripheral = peripheral as? CBPeripheral {
            centralDelegate?.centralManager?(callbackCentral, didDisconnectPeripheral: cbPeripheral, error: error)
            return
        }

        // 非 CBPeripheral 的注入式测试场景，走内部兜底回调。
        (centralDelegate as? AsyncBleManager)?.handleDidDisconnect(peripheral: peripheral, error: error)
    }
}

import Foundation
import CoreBluetooth
import FXBlueToothCore
@testable import FXBlueToothCombine

@available(iOS 13.0, macOS 10.15, *)
final class MockCentralManager: CentralManagerProtocol {

    private final class CallbackCentralCarrier: NSObject {}

    var state: CBManagerState = .poweredOn {
        didSet { notifyStateUpdate() }
    }
    var centralDelegate: CBCentralManagerDelegate? = nil {
        didSet { notifyStateUpdate() }
    }

    // Call records
    var scanWasCalled = false
    var stopScanCalled = false
    var scanCalledWithServices: [CBUUID]? = nil
    var connectCalledWith: CBPeripheral? = nil
    var cancelConnectionCalledWithIdentifier: UUID? = nil
    var eventLog: [String] = []

    // Auto-callback flags
    var autoCallbackConnectResultOnConnect: Bool = false
    var connectErrorOnConnect: Error? = nil
    var autoCallbackDisconnectOnCancel: Bool = false
    var disconnectErrorOnCancel: Error? = nil

    struct ScanDiscoveryEvent {
        let peripheral: CBPeripheral
        let advertisementData: [String: Any]
        let rssi: NSNumber
        let delayNanoseconds: UInt64
        init(peripheral: CBPeripheral,
             advertisementData: [String: Any] = [:],
             rssi: NSNumber = 0,
             delayNanoseconds: UInt64 = 5_000_000) {
            self.peripheral = peripheral
            self.advertisementData = advertisementData
            self.rssi = rssi
            self.delayNanoseconds = delayNanoseconds
        }
    }
    var autoCallbackDiscoveriesOnScan: Bool = false
    var discoveriesOnScan: [ScanDiscoveryEvent] = []

    private lazy var callbackCentral = unsafeBitCast(CallbackCentralCarrier(), to: CBCentralManager.self)

    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {
        scanWasCalled = true
        scanCalledWithServices = serviceUUIDs
        eventLog.append("scan")
        guard autoCallbackDiscoveriesOnScan else { return }
        for event in discoveriesOnScan {
            Task {
                try? await Task.sleep(nanoseconds: event.delayNanoseconds)
                self.notifyDidDiscover(peripheral: event.peripheral,
                                       advertisementData: event.advertisementData,
                                       rssi: event.rssi)
            }
        }
    }

    func stopScan() {
        stopScanCalled = true
        eventLog.append("stopScan")
    }

    func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {
        connectCalledWith = peripheral
        eventLog.append("connect")
        guard autoCallbackConnectResultOnConnect else { return }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            if let err = self.connectErrorOnConnect {
                self.notifyDidFailToConnect(peripheral: peripheral, error: err)
            } else {
                self.notifyDidConnect(peripheral: peripheral)
            }
        }
    }

    func cancelPeripheralConnection(_ peripheral: any PeripheralProtocol) {
        cancelConnectionCalledWithIdentifier = peripheral.identifier
        eventLog.append("cancel")
        guard autoCallbackDisconnectOnCancel else { return }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000)
            self.notifyDidDisconnect(peripheral: peripheral, error: self.disconnectErrorOnCancel)
        }
    }

    // MARK: - Notify

    func notifyStateUpdate() {
        centralDelegate?.centralManagerDidUpdateState(callbackCentral)
    }

    func notifyDidDiscover(peripheral: CBPeripheral,
                           advertisementData: [String: Any] = [:],
                           rssi: NSNumber = 0) {
        centralDelegate?.centralManager?(callbackCentral,
                                         didDiscover: peripheral,
                                         advertisementData: advertisementData,
                                         rssi: rssi)
    }

    func notifyDidConnect(peripheral: CBPeripheral) {
        centralDelegate?.centralManager?(callbackCentral, didConnect: peripheral)
    }

    func notifyDidFailToConnect(peripheral: CBPeripheral, error: Error?) {
        centralDelegate?.centralManager?(callbackCentral, didFailToConnect: peripheral, error: error)
    }

    func notifyDidDisconnect(peripheral: any PeripheralProtocol, error: Error?) {
        if let cb = peripheral as? CBPeripheral {
            centralDelegate?.centralManager?(callbackCentral, didDisconnectPeripheral: cb, error: error)
            return
        }
        (centralDelegate as? CentralDelegateBridge)?.handleDidDisconnect(peripheral: peripheral, error: error)
    }
}

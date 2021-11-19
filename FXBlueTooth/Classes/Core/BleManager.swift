//
//  BleManager.swift
//  BleManager
//
//  Created by mac on 2021/4/30.
//

import Foundation
import CoreBluetooth
import SwiftyBeaver

public let bleLogger = SwiftyBeaver.self

public enum BleManagerError: Error {
    public enum CentralStateReason {
        case unknown
        case resetting
        case unsupported
        case unauthorized
        case poweredOff
    }
    public enum CentralConnectReason {
        case failToConnect(Error?)
    }
    
    case centralStateError(reason: CentralStateReason)
    case centralConnectError(reason: CentralConnectReason)
    case custom(String)
}

public class PeripheralInfo: Equatable {
    
    public let peripheral: CBPeripheral
    public var advertisementData: [String : Any]
    public var rssi: NSNumber?
    
    init(peripheral: CBPeripheral, advertisementData: [String : Any]) {
        self.peripheral = peripheral
        self.advertisementData = advertisementData
    }
    
    public static func == (lhs: PeripheralInfo, rhs: PeripheralInfo) -> Bool {
        return lhs.peripheral.identifier == rhs.peripheral.identifier
    }
}

public class BleManager {
    
    public typealias Handler = (Result<CBPeripheral, BleManagerError>) -> Void
    let centralManager: CentralManager
    
    public init(options: [String : Any]? = nil) {
        centralManager = CentralManager(options: options)
    }
    
    public func execute(
        command: BleManagerCommand? = nil,
        handler: Handler? = nil) {
        centralManager.execute(command: command, handler: handler)
    }
    
    public func execute(
        commandItems: [BleManagerCommandItem]? = nil,
        handler: Handler? = nil) {
        centralManager.execute(command: BleManagerCommand(commandItems), handler: handler)
    }
}

extension BleManager {
    class CentralManager: NSObject, CBCentralManagerDelegate {
        
        let centralManager: CBCentralManager
        let multiDelegate = CentralManagerMultiDelegate()
        private var command: BleManagerCommand?
        private var handler: Handler?
        private var discoverPeripheral: [PeripheralInfo] = []
        private(set) var restorePeripheral: [CBPeripheral] = []
        
        init(options: [String : Any]? = nil) {
            centralManager = CBCentralManager(delegate: multiDelegate, queue: nil, options: options)
            super.init()
            multiDelegate.addDelegate(self)
        }
        
        private func handlerComplete(_ completion: Result<CBPeripheral, BleManagerError>) {
            centralManager.stopScan()
            handler?(completion)
            handler = nil
        }
        
        func execute(
            command: BleManagerCommand? = nil,
            handler: Handler? = nil) {
            
            centralManager.stopScan()
            discoverPeripheral.removeAll()
            
            self.command = command
            self.handler = handler
            
            if let cancelConnect = command?.cancelConnect {
                centralManager.cancelPeripheralConnection(cancelConnect)
            } else {
                if let connect = command?.connect,
                   let retrieveConnected = command?.retrieveConnected {
                    if let peripheral = centralManager
                     .retrieveConnectedPeripherals(withServices: retrieveConnected)
                        .first(where: { $0.identifier.uuidString == connect }) {
                        centralManager.connect(peripheral, options: command?.connectInfo)
                    } else if let peripheral = restorePeripheral.first(where: { $0.identifier.uuidString == connect }) {
                        centralManager.connect(peripheral, options: command?.connectInfo)
                    } else {
                        centralManagerDidUpdateState(centralManager)
                    }
                } else {
                    centralManagerDidUpdateState(centralManager)
                }
            }
        }
        
        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            switch central.state {
            case .unknown:
                handlerComplete(.failure(.centralStateError(reason: .unknown)))
            case .resetting:
                handlerComplete(.failure(.centralStateError(reason: .resetting)))
            case .unsupported:
                handlerComplete(.failure(.centralStateError(reason: .unsupported)))
            case .unauthorized:
                handlerComplete(.failure(.centralStateError(reason: .unauthorized)))
            case .poweredOff:
                handlerComplete(.failure(.centralStateError(reason: .poweredOff)))
            case .poweredOn:
                centralManager.scanForPeripherals(withServices: command?.scanServices, options: command?.scanOptions)
            @unknown default:
                break
            }
        }
        
        func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
            guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else { return }
            restorePeripheral = peripherals
        }
        
        func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
            if let peripheralInfo = discoverPeripheral.first(where: { $0.peripheral == peripheral }) {
                peripheralInfo.advertisementData = advertisementData
                peripheralInfo.rssi = RSSI
            } else {
                let info = PeripheralInfo(peripheral: peripheral, advertisementData: advertisementData)
                if let filter = command?.filter,
                   let peripheralInfo = filter.filter(peripheralInfo: info) {
                    discoverPeripheral.append(peripheralInfo)
                } else {
                    discoverPeripheral.append(info)
                }
            }
            if let discover = command?.discover {
                discover.discover(peripheralGroup: discoverPeripheral)
            }
            if let connectuuid = command?.connect,
               let info = discoverPeripheral.first(where: { $0.peripheral.identifier.uuidString == connectuuid }) {
                central.connect(info.peripheral, options: command?.connectInfo)
            }
        }
        
        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            handlerComplete(.success(peripheral))
            command?.handle?.peripheral = peripheral
        }
        
        func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            handlerComplete(.failure(.centralConnectError(reason: .failToConnect(error))))
        }
        
        func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
            bleLogger.debug("断开连接成功:\(peripheral.name ?? "")")
            if let error = error {
                bleLogger.error(error)
            }
            command?.didDisConnect?.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
            handlerComplete(.success(peripheral))
        }
        
        
    }
}



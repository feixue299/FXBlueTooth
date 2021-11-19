//
//  BleManagerCommand.swift
//  BleManager
//
//  Created by mac on 2021/4/30.
//

import Foundation
import CoreBluetooth

public protocol PeripheralFilter {
    func filter(peripheralInfo: PeripheralInfo) -> PeripheralInfo?
}

public protocol DiscoverPeripheral {
    func discover(peripheralGroup: [PeripheralInfo])
}

public protocol PeripheralHandler {
    var peripheral: CBPeripheral? { set get }
}

public protocol PeripheralDidDisConnect {
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
}

public enum BleManagerCommandItem {
    case scanServices([CBUUID])
    case scanOptions([String: Any])
    case discover(DiscoverPeripheral)
    case filter(PeripheralFilter)
    case connect(uuid: String)
    case retrieveConnected(services: [CBUUID])
    case connectInfo([String : Any])
    case handle(PeripheralHandler)
    case cancelConnect(CBPeripheral)
    case didDisConnect(PeripheralDidDisConnect)
}

public struct BleManagerCommand {
    public var scanServices: [CBUUID]?
    public var scanOptions: [String: Any]?
    public var discover: DiscoverPeripheral?
    public var filter: PeripheralFilter?
    public var connect: String?
    public var retrieveConnected: [CBUUID]?
    public var connectInfo: [String : Any]?
    public var handle: PeripheralHandler?
    public var cancelConnect: CBPeripheral?
    public var didDisConnect: PeripheralDidDisConnect?
    
    public init(_ items: [BleManagerCommandItem]?) {
        guard let items = items else { return }
        for item in items {
            switch item {
            case .scanServices(let value): scanServices = value
            case .scanOptions(let value): scanOptions = value
            case .discover(let value): discover = value
            case .filter(let value): filter = value
            case .connect(let value): connect = value
            case .connectInfo(let value): connectInfo = value
            case .retrieveConnected(let value): retrieveConnected = value
            case .handle(let value): handle = value
            case .cancelConnect(let value): cancelConnect = value
            case .didDisConnect(let value): didDisConnect = value
            }
        }
    }
}

//
//  PeripheralCommand.swift
//  BleManager
//
//  Created by mac on 2021/5/10.
//

import Foundation
import CoreBluetooth

public protocol DiscoverCharacteristic {
    func didDiscoverCharacteristicsFor(service: CBService)
}

public protocol CharacteristicValue {
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
}

public enum PeripheralCommandItem {
    case discoverServices([CBUUID])
    case discoverCharacteristics([DiscoverCharacteristic])
    case characteristicValues([CharacteristicValue])
}

public struct PeripheralCommand {
    public var discoverServices: [CBUUID]?
    public var discoverCharacteristics: [DiscoverCharacteristic]?
    public var characteristicValues: [CharacteristicValue]?
    
    public init(_ items: [PeripheralCommandItem]?) {
        guard let items = items else { return }
        for item in items {
            switch item {
            case .discoverServices(let value): discoverServices = value
            case .discoverCharacteristics(let value): discoverCharacteristics = value
            case .characteristicValues(let value): characteristicValues = value
            }
        }
    }
}

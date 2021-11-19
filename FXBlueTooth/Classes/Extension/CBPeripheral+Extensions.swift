//
//  CBPeripheral+Extensions.swift
//  HTBleManager
//
//  Created by mac on 2021/8/27.
//

import Foundation
import CoreBluetooth

@objc
public extension CBPeripheral {
    func autoWriteValue(_ data: Data?, forCharacteristic characteristic: CBCharacteristic?) {
        guard let data = data, let characteristic = characteristic else { return }
        if characteristic.properties.contains(.writeWithoutResponse) {
            writeValue(data, for: characteristic, type: .withoutResponse)
        } else if characteristic.properties.contains(.write) {
            writeValue(data, for: characteristic, type: .withResponse)
        }
    }
}

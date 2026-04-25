//
//  CBPeripheral+Extensions.swift
//  HTBleManager
//
//  Created by mac on 2021/8/27.
//

import Foundation
import CoreBluetooth

/// CBPeripheral 的便捷扩展，提供自动判断写入类型的方法。
@objc
public extension CBPeripheral {
    /// 根据特征值的属性自动选择写入类型并发送数据。
    /// 若特征值支持 writeWithoutResponse 则使用无响应写入，否则使用有响应写入。
    /// - Parameters:
    ///   - data: 要写入的数据，为 nil 时直接返回
    ///   - characteristic: 目标特征值，为 nil 时直接返回
    func autoWriteValue(_ data: Data?, forCharacteristic characteristic: CBCharacteristic?) {
        guard let data = data, let characteristic = characteristic else { return }
        if characteristic.properties.contains(.writeWithoutResponse) {
            // 特征值支持无响应写入，使用 withoutResponse 类型（速度更快）
            writeValue(data, for: characteristic, type: .withoutResponse)
        } else if characteristic.properties.contains(.write) {
            // 特征值仅支持有响应写入，使用 withResponse 类型（可靠性更高）
            writeValue(data, for: characteristic, type: .withResponse)
        }
    }
}

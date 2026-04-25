//
//  PeripheralCommand.swift
//  BleManager
//
//  Created by mac on 2021/5/10.
//

import Foundation
import CoreBluetooth

/// 特征值发现回调协议。
/// 当外设完成某个 Service 下的特征值发现时，通知实现者进行处理。
public protocol DiscoverCharacteristic {
    /// 外设发现指定 Service 的特征值后回调
    /// - Parameter service: 已完成特征值发现的 CBService 对象
    func didDiscoverCharacteristicsFor(service: CBService)
}

/// 特征值数据读写回调协议。
/// 监听外设特征值的写入、更新及通知状态变化事件。
public protocol CharacteristicValue {
    /// 外设完成特征值写入后回调
    /// - Parameters:
    ///   - peripheral: 目标外设
    ///   - characteristic: 被写入的特征值
    ///   - error: 写入失败时的错误信息，成功则为 nil
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)

    /// 外设特征值数据更新后回调（收到通知或读取响应）
    /// - Parameters:
    ///   - peripheral: 目标外设
    ///   - characteristic: 数据已更新的特征值
    ///   - error: 更新失败时的错误信息，成功则为 nil
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)

    /// 外设特征值通知订阅状态变化后回调
    /// - Parameters:
    ///   - peripheral: 目标外设
    ///   - characteristic: 通知状态已变化的特征值
    ///   - error: 操作失败时的错误信息，成功则为 nil
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
}

/// 外设操作命令条目枚举，用于以 DSL 风格构建 `PeripheralCommand`。
public enum PeripheralCommandItem {
    /// 需要发现的 Service UUID 列表
    case discoverServices([CBUUID])
    /// 特征值发现处理器列表
    case discoverCharacteristics([DiscoverCharacteristic])
    /// 特征值数据读写处理器列表
    case characteristicValues([CharacteristicValue])
}

/// 外设操作命令结构体，聚合连接后对外设进行服务/特征值发现及数据交互所需的全部配置。
public struct PeripheralCommand {
    /// 需要发现的 Service UUID 列表，传 nil 则发现所有 Service
    public var discoverServices: [CBUUID]?
    /// 特征值发现完成后的处理器列表
    public var discoverCharacteristics: [DiscoverCharacteristic]?
    /// 特征值数据读写事件的处理器列表
    public var characteristicValues: [CharacteristicValue]?

    /// 通过命令条目数组初始化，自动解析并填充各字段
    /// - Parameter items: `PeripheralCommandItem` 数组，传 nil 则所有字段保持默认值
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

//
//  PeripheralOperationCommand.swift
//  FXBlueTooth
//
//  Created by hard on 2021/12/30.
//

import Foundation

/// 外设操作指令协议，定义向蓝牙外设发送指令并处理响应的完整接口。
/// 实现此协议以描述一条具体的蓝牙通信指令，包括发送内容、响应校验、数据过滤及超时配置。
public protocol PeripheralOperationCommand {
    /// 要发送给外设的原始指令数据
    var cmdData: Data { get }

    /// 校验外设返回的响应数据，判断是否满足完成条件
    /// - Parameters:
    ///   - dataGroup: 已缓存的历史数据包数组
    ///   - data: 本次经过 `filterData` 过滤后的新数据
    /// - Returns: `CheckResponseResult` 枚举，描述本次校验结果
    func checkResponse(_ dataGroup: [Data], data: Data) -> CheckResponseResult

    /// 对外设原始返回数据进行预处理/过滤，返回 nil 表示忽略该数据包
    /// - Parameter data: 外设返回的原始数据
    /// - Returns: 过滤后的有效数据，若返回 nil 则跳过本次数据
    func filterData(_ data: Data) -> Data?

    /// 返回本指令使用的分包长度策略
    /// - Returns: 遵循 `PeripheralCommandLengthProtocol` 的分包策略对象
    func getLengthProtocol() -> PeripheralCommandLengthProtocol

    /// 指令超时时间（秒），超时后自动以失败结束任务
    var timeOutInterval: TimeInterval { get }
}

/// 为 `PeripheralOperationCommand` 提供默认实现，简化常规指令的接入成本。
public extension PeripheralOperationCommand {
    /// 默认使用 `DefaultPeripheralCommandLength`（每包 20 字节）
    func getLengthProtocol() -> PeripheralCommandLengthProtocol {
        return DefaultPeripheralCommandLength()
    }

    /// 默认超时时间为 20 秒
    var timeOutInterval: TimeInterval {
        return 20
    }
}

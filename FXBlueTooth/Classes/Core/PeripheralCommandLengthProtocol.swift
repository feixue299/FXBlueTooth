//
//  PeripheralCommandLengthProtocol.swift
//  FXBlueTooth
//
//  Created by hard on 2021/12/30.
//

import Foundation

/// 蓝牙指令分包长度协议。
/// 实现此协议可自定义每次向外设写入数据时的最大字节数，
/// 用于处理 BLE MTU 限制下的数据分包发送场景。
public protocol PeripheralCommandLengthProtocol {
    /// 返回当前分包的最大字节长度
    /// - Returns: 本次写入允许的最大字节数
    func currentLength() -> Int
}

/// 固定长度分包策略，每次分包长度保持一致。
public class DefaultPeripheralCommandLength: PeripheralCommandLengthProtocol {

    /// 每次分包的固定字节长度
    public let length: Int

    /// 初始化固定长度分包策略
    /// - Parameter length: 每包字节数，默认为 20（BLE 标准 ATT MTU 默认负载大小）
    public init(length: Int = 20) {
        self.length = length
    }

    /// 返回固定的分包长度
    public func currentLength() -> Int {
        return length
    }
}

/// 首包特殊长度分包策略：第一包使用 `first` 长度，后续包使用 `then` 长度。
/// 适用于协议头部与数据体长度不同的场景。
public class FirstPeripheralCommandLength: PeripheralCommandLengthProtocol {

    /// 第一包的字节长度
    public let first: Int
    /// 后续包的字节长度
    public let then: Int

    /// 标记是否还未发送第一包
    private var firstValue = true

    /// 初始化首包特殊长度分包策略
    /// - Parameters:
    ///   - first: 第一包的最大字节数
    ///   - then: 后续每包的最大字节数
    public init(first: Int, then: Int) {
        self.first = first
        self.then = then
    }

    /// 返回当前分包长度：首次调用返回 `first`，之后返回 `then`
    public func currentLength() -> Int {
        if firstValue {
            firstValue = false  // 标记第一包已发送
            return first
        } else {
            return then
        }
    }
}

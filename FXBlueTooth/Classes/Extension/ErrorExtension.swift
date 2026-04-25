//
//  ErrorExtension.swift
//  BleManager
//
//  Created by mac on 2021/5/24.
//

import Foundation

/// NSError 的便捷扩展，提供统一的蓝牙模块错误创建方法。
public extension NSError {
    /// 创建一个蓝牙模块专用的 NSError 实例
    /// - Parameter description: 错误的本地化描述文字
    /// - Returns: domain 为 "BleManager Module"、code 为 -1 的 NSError 对象
    static func error(description: String) -> NSError {
        return NSError(domain: "BleManager Module", code: -1, userInfo: [NSLocalizedDescriptionKey: description])
    }
}

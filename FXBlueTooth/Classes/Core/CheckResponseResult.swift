//
//  CheckResponseResult.swift
//  FXBlueTooth
//
//  Created by hard on 2021/12/30.
//

import Foundation

/// 蓝牙指令响应校验结果枚举。
/// 用于描述对外设返回数据进行校验后的处理意图，
/// 由 `PeripheralOperationCommand.checkResponse` 方法返回。
public enum CheckResponseResult {
    /// 匹配成功，携带完整的响应数据包数组
    case success(data: [Data])
    /// 匹配失败，携带具体的错误信息
    case failure(error: Error)
    /// 数据不完整，需要继续等待后续数据包，携带当前已缓存的数据
    case goon(data: [Data])
    /// 长连接模式，持续接收数据而不结束任务，携带本次收到的数据
    case longConnection(data: [Data])
}

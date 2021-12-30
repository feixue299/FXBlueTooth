//
//  CheckResponseResult.swift
//  FXBlueTooth
//
//  Created by hard on 2021/12/30.
//

import Foundation

public enum CheckResponseResult {
    /// 匹配成功
    case success(data: [Data])
    /// 匹配失败
    case failure(error: Error)
    /// 继续匹配
    case goon(data: [Data])
    /// 长连接
    case longConnection(data: [Data])
}

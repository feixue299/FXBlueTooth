//
//  Weak.swift
//  HTBleManager
//
//  Created by mac on 2021/7/17.
//

import Foundation

/// 弱引用包装器，用于在集合中存储对象的弱引用，避免循环引用和内存泄漏。
/// 泛型参数 T 必须是引用类型（AnyObject）。
class Weak<T: AnyObject>: NSObject {
    /// 被弱引用持有的对象，当对象被释放后自动置为 nil
    weak var value: T?

    /// 初始化弱引用包装器
    /// - Parameter value: 需要被弱引用持有的对象
    init(value: T) {
        self.value = value
    }
}

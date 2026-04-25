//
//  BlueToothAnyTaskModel.swift
//  BleManager
//
//  Created by mac on 2021/7/31.
//

import Foundation

/// 类型擦除的蓝牙任务模型包装器。
/// 将泛型 `BlueToothTaskModel<T>` 转换为 `BlueToothTaskModel<Any>`，
/// 使不同泛型类型的任务可以统一存储和调度，常用于任务队列管理。
@objc
@objcMembers
open class BlueToothAnyTaskModel: NSObject {

    /// 内部持有的类型擦除后的任务模型（泛型参数为 Any）
    public let task: BlueToothTaskModel<Any>

    /// 任务的数据解析策略（已类型擦除为 Any）
    public var parse: BlueToothTaskParseValue<Any> {
        return task.parse
    }

    /// 将任意泛型类型的 `BlueToothTaskModel<T>` 包装为类型擦除版本
    /// - Parameter task: 原始泛型任务模型
    public init<T>(task: BlueToothTaskModel<T>) {

        // 将原始解析闭包包装为返回 Any 的闭包，保持原有解析逻辑
        let parse: BlueToothTaskParseValue<Any>
        switch task.parse {
        case .value1(let value):
            // 多包解析：包装为接收 [Data] 返回 Any 的闭包
            parse = .value1({ datas in
                value(datas)
            })
        case .value2(let value):
            // 单包解析：包装为接收 Data 返回 Any 的闭包
            parse = .value2({ data in
                value(data)
            })
        }

        // 将原始插件回调列表转换为接收 Any 的版本，内部强转回原始类型 T
        let plugins: [BlueToothTaskComplete<Any>] = task.plugins.map { closure in
            { value in
                closure(value as! T)  // 类型擦除后强转，调用方需保证类型一致
            }
        }

        // 根据指令来源类型分别构建类型擦除后的任务模型
        switch task.eitherOrValued {
        case .value1(let value):
            // 直接指令：使用已有指令对象构建
            self.task = BlueToothTaskModel<Any>.init(command: value, parse: parse, plugins: plugins)
        case .value2(let value):
            // 延迟指令：使用创建闭包构建
            self.task = BlueToothTaskModel<Any>.init(createCommandClosure: value, parse: parse, plugins: plugins)
        }
    }
}

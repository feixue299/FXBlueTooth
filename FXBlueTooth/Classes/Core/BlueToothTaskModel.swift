//
//  BlueToothTaskModel.swift
//  HTBleManager
//
//  Created by mac on 2021/7/30.
//

import Foundation

/// 支持外部设置操作指令的协议，用于延迟创建指令的场景。
public protocol CreateCommandProtocol {
    /// 接收外部传入的操作指令
    /// - Parameter command: 遵循 `PeripheralOperationCommand` 的指令对象，可为 nil
    func setCommand(_ command: PeripheralOperationCommand?)
}

/// 二选一值枚举，用于在两种不同类型的值之间做选择，避免使用可选类型。
public enum EitherOrValued<Value1, Value2> {
    /// 第一种值
    case value1(Value1)
    /// 第二种值
    case value2(Value2)
}

/// 蓝牙任务的数据解析闭包类型别名。
/// - value1: 接收多包数据数组并返回解析结果
/// - value2: 接收单包数据并返回解析结果
public typealias BlueToothTaskParseValue<Result> = EitherOrValued<(([Data]) -> Result), ((Data) -> Result)>

/// 蓝牙任务完成回调类型别名，接收解析后的结果值。
public typealias BlueToothTaskComplete<T> = (T) -> Void

/// 蓝牙任务模型，封装一条完整的蓝牙通信任务，包括指令、数据解析和完成回调插件。
/// 泛型参数 T 为任务解析结果的类型。
open class BlueToothTaskModel<T>: NSObject, CreateCommandProtocol {

    /// 延迟创建指令的闭包类型，接收 `CreateCommandProtocol` 以便异步回传指令
    public typealias CreateCommandClosure = ((CreateCommandProtocol) -> Void)

    /// 指令来源：直接提供指令对象（value1）或通过闭包延迟创建（value2）
    let eitherOrValued: EitherOrValued<PeripheralOperationCommand, CreateCommandClosure>

    /// 数据解析策略：多包解析（value1）或单包解析（value2）
    public let parse: BlueToothTaskParseValue<T>

    /// 任务完成后依次执行的插件回调列表
    private(set) var plugins: [BlueToothTaskComplete<T>] = []

    /// 使用已有指令对象初始化任务模型
    /// - Parameters:
    ///   - command: 遵循 `PeripheralOperationCommand` 的指令对象
    ///   - parse: 数据解析策略
    ///   - plugins: 完成回调插件列表
    public init(command: PeripheralOperationCommand, parse: BlueToothTaskParseValue<T>, plugins: [BlueToothTaskComplete<T>]) {
        self.eitherOrValued = .value1(command)
        self.parse = parse
        self.plugins = plugins
    }

    /// 使用延迟创建指令的闭包初始化任务模型，适用于指令需要动态生成的场景
    /// - Parameters:
    ///   - createCommandClosure: 创建指令的闭包，闭包内通过 `CreateCommandProtocol.setCommand` 回传指令
    ///   - parse: 数据解析策略
    ///   - plugins: 完成回调插件列表
    public init(createCommandClosure: @escaping CreateCommandClosure, parse: BlueToothTaskParseValue<T>, plugins: [BlueToothTaskComplete<T>]) {
        self.eitherOrValued = .value2(createCommandClosure)
        self.parse = parse
        self.plugins = plugins
    }

    /// 追加一个任务完成回调插件
    /// - Parameter closure: 任务完成时执行的回调，接收解析结果
    public func addPlugin(_ closure: @escaping BlueToothTaskComplete<T>) {
        plugins.append(closure)
    }

    /// 准备指令完成后的回调闭包，用于延迟创建指令场景下的内部通知
    private var prepareCommandClosure: ((BlueToothTaskModel<T>, PeripheralOperationCommand?) -> Void)?

    /// 准备指令并在就绪后执行回调。
    /// 若指令已存在则立即回调；若为延迟创建则触发创建闭包，等待 `setCommand` 回传。
    /// - Parameter closure: 指令就绪后的回调，参数为当前任务模型和指令对象
    public func prepareCommand(_ closure: @escaping ((BlueToothTaskModel<T>, PeripheralOperationCommand?) -> Void)) {
        switch eitherOrValued {
        case .value1(let command):
            // 指令已存在，直接回调
            closure(self, command)
        case .value2(let createCommandClosure):
            // 指令需延迟创建，保存回调并触发创建闭包
            self.prepareCommandClosure = closure
            createCommandClosure(self)
        }
    }

    /// 内部方法：接收延迟创建的指令并触发已保存的准备回调
    /// - Parameter command: 外部通过 `setCommand` 传入的指令对象
    private func receiveCommand(_ command: PeripheralOperationCommand?) {
        self.prepareCommandClosure?(self, command)
        self.prepareCommandClosure = nil  // 回调执行后清空，防止重复触发
    }

    /// 实现 `CreateCommandProtocol`，接收外部传入的指令并触发准备回调
    /// - Parameter command: 外部传入的操作指令
    public func setCommand(_ command: PeripheralOperationCommand?) {
        receiveCommand(command)
    }

    /// 将解析结果分发给所有已注册的插件回调
    /// - Parameter value: 任务解析完成后的结果值
    public func completeValue(_ value: T) {
        for plugin in plugins {
            plugin(value)
        }
    }
}

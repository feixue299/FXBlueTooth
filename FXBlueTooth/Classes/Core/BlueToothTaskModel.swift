//
//  BlueToothTaskModel.swift
//  HTBleManager
//
//  Created by mac on 2021/7/30.
//

import Foundation

public protocol CreateCommandProtocol {
    func setCommand(_ command: PeripheralOperationCommand?)
}

public enum EitherOrValued<Value1, Value2> {
    case value1(Value1)
    case value2(Value2)
}

public typealias BlueToothTaskParseValue<Result> = EitherOrValued<(([Data]) -> Result), ((Data) -> Result)>
public typealias BlueToothTaskComplete<T> = (T) -> Void

open class BlueToothTaskModel<T>: NSObject, CreateCommandProtocol {
    
    public typealias CreateCommandClosure = ((CreateCommandProtocol) -> Void)
    
    let eitherOrValued: EitherOrValued<PeripheralOperationCommand, CreateCommandClosure>
    public let parse: BlueToothTaskParseValue<T>
    private(set) var plugins: [BlueToothTaskComplete<T>] = []
    
    public init(command: PeripheralOperationCommand, parse: BlueToothTaskParseValue<T>, plugins: [BlueToothTaskComplete<T>]) {
        self.eitherOrValued = .value1(command)
        self.parse = parse
        self.plugins = plugins
    }
    
    public init(createCommandClosure: @escaping CreateCommandClosure, parse: BlueToothTaskParseValue<T>, plugins: [BlueToothTaskComplete<T>]) {
        self.eitherOrValued = .value2(createCommandClosure)
        self.parse = parse
        self.plugins = plugins
    }
    
    public func addPlugin(_ closure: @escaping BlueToothTaskComplete<T>) {
        plugins.append(closure)
    }
    
    private var prepareCommandClosure: ((BlueToothTaskModel<T>, PeripheralOperationCommand?) -> Void)?
    public func prepareCommand(_ closure: @escaping ((BlueToothTaskModel<T>, PeripheralOperationCommand?) -> Void)) {
        switch eitherOrValued {
        case .value1(let command):
            closure(self, command)
        case .value2(let createCommandClosure):
            self.prepareCommandClosure = closure
            createCommandClosure(self)
        }
    }
    
    private func receiveCommand(_ command: PeripheralOperationCommand?) {
        self.prepareCommandClosure?(self, command)
        self.prepareCommandClosure = nil
    }
    
    public func setCommand(_ command: PeripheralOperationCommand?) {
        receiveCommand(command)
    }
    
    public func completeValue(_ value: T) {
        for plugin in plugins {
            plugin(value)
        }
    }
}




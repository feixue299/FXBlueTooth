//
//  BlueToothAnyTaskModel.swift
//  BleManager
//
//  Created by mac on 2021/7/31.
//

import UIKit

@objc
@objcMembers
open class BlueToothAnyTaskModel: NSObject {
    public let task: BlueToothTaskModel<Any>
    
    public var parse: BlueToothTaskParseValue<Any> {
        return task.parse
    }
    
    public init<T>(task: BlueToothTaskModel<T>) {
                
        let parse: BlueToothTaskParseValue<Any>
        switch task.parse {
        case .value1(let value):
            parse = .value1({ datas in
                value(datas)
            })
        case .value2(let value):
            parse = .value2({ data in
                value(data)
            })
        }
        let plugins: [BlueToothTaskComplete<Any>] = task.plugins.map { closure in
            { value in
                closure(value as! T)
            }
        }
        switch task.eitherOrValued {
        case .value1(let value):
            self.task = BlueToothTaskModel<Any>.init(command: value, parse: parse, plugins: plugins)
        case .value2(let value):
            self.task = BlueToothTaskModel<Any>.init(createCommandClosure: value, parse: parse, plugins: plugins)
        }
    }
    
}

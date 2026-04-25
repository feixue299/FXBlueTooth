//
//  CharacteristicAdapter.swift
//  BleManager
//
//  Created by mac on 2021/8/31.
//

import Foundation

/// 特征值适配器，负责监听读写特征值的发现状态，并在两者均就绪后通知外部可以开始发送指令。
/// 通过 KVO 观察 `Characteristic` 的读写特征值属性，自动同步到 `DeviceCharacteristicValue`，
/// 并在读写特征值均可用时触发就绪回调。
public class CharacteristicAdapter: NSObject {

    /// 特征值就绪回调类型，参数为已配置好读写特征值的 `DeviceCharacteristicValue`
    public typealias ReadyClousre = (PeripheralDevice.DeviceCharacteristicValue) -> Void

    /// 被监听的特征值描述对象（包含读写 UUID 及已发现的特征值引用）
    public let characteristic: PeripheralDevice.Characteristic

    /// 与特征值绑定的数据交互对象，持有实际的读写 `CBCharacteristic`
    public let characteristicValue: PeripheralDevice.DeviceCharacteristicValue

    /// KVO 观察者持有列表，防止观察者提前释放
    private var keyValueObservation: [NSKeyValueObservation] = []

    /// 标记读写特征值是否均已就绪，变为 true 时触发所有等待中的就绪回调
    private var readyForCommand = false {
        didSet {
            if readyForCommand {
                // 读写特征值均已就绪，依次执行所有等待中的回调
                readyForCommandClosureGroup.forEach { closure in
                    closure(characteristicValue)
                }
            }
        }
    }

    /// 等待就绪的回调队列，在特征值未就绪时暂存，就绪后统一触发
    private var readyForCommandClosureGroup: [ReadyClousre] = []

    /// 初始化特征值适配器，开始 KVO 监听读写特征值的发现状态
    /// - Parameters:
    ///   - characteristic: 特征值描述对象，提供读写 UUID 及发现回调
    ///   - characteristicValue: 数据交互对象，用于实际的指令收发
    public init(characteristic: PeripheralDevice.Characteristic, characteristicValue: PeripheralDevice.DeviceCharacteristicValue) {
        self.characteristic = characteristic
        self.characteristicValue = characteristicValue
        super.init()

        // 监听读特征值的发现：发现后同步到 characteristicValue 并开启通知订阅
        keyValueObservation.append(characteristic.observe(\.readCharacteristic, options: .new) { [weak self] objc, value in
            guard let newValue = value.newValue,
                  let readCharacteristic = newValue,
                  let self = self else { return }
            self.characteristicValue.readCharacteristic = readCharacteristic
            // 订阅读特征值的通知，以便接收外设主动推送的数据
            self.characteristicValue.peripheral?.setNotifyValue(true, for: readCharacteristic)
            // 读特征值就绪，检查写特征值是否也已就绪
            self.readyForCommand = self.characteristicValue.writeCharacteristic != nil
        })

        // 监听写特征值的发现：发现后同步到 characteristicValue
        keyValueObservation.append(characteristic.observe(\.writeCharacteristic, options: .new, changeHandler: { [weak self] objec, value in
            guard let newValue = value.newValue,
                  let writeCharacteristic = newValue,
                  let self = self else { return }
            self.characteristicValue.writeCharacteristic = writeCharacteristic
            // 写特征值就绪，检查读特征值是否也已就绪
            self.readyForCommand = self.characteristicValue.readCharacteristic != nil
        }))
    }

    /// 注册特征值就绪回调。
    /// 若读写特征值已均就绪则立即执行回调，否则加入等待队列，待就绪后自动触发。
    /// - Parameter closure: 就绪后执行的回调，参数为已配置好的 `DeviceCharacteristicValue`
    public func readyForCommand(_ closure: @escaping ((PeripheralDevice.DeviceCharacteristicValue) -> Void)) {
        if readyForCommand {
            // 已就绪，立即回调
            closure(characteristicValue)
        } else {
            // 未就绪，加入等待队列
            readyForCommandClosureGroup.append(closure)
        }
    }
}

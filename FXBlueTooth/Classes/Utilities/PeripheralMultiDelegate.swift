//
//  PeripheralMultiDelegate.swift
//  HTComponents
//
//  Created by mac on 2021/7/3.
//

import Foundation
import CoreBluetooth

/// 外设多播代理，实现 `CBPeripheralDelegate` 并将所有回调广播给已注册的多个代理对象。
/// 通过弱引用持有代理，避免循环引用。适用于需要多个模块同时监听同一外设事件的场景。
@objcMembers
open class PeripheralMultiDelegate: NSObject, CBPeripheralDelegate {

    /// 已注册的代理弱引用列表
    var delegateGroup: [Weak<CBPeripheralDelegate>] = []

    /// 注册一个新的代理对象。若该代理已存在则不重复添加。
    /// - Parameter delegate: 需要接收回调的 `CBPeripheralDelegate` 对象
    public func addDelegate(_ delegate: CBPeripheralDelegate) {
        if !delegateGroup.contains(where: { $0.value === delegate }) {
            delegateGroup.append(Weak(value: delegate))
        }
    }

    /// 移除已注册的代理对象
    /// - Parameter delegate: 需要移除的 `CBPeripheralDelegate` 对象
    public func removeDelegate(_ delegate: CBPeripheralDelegate) {
        guard let index = delegateGroup.firstIndex(where: { $0.value === delegate }) else { return }
        delegateGroup.remove(at: index)
    }

    // MARK: - CBPeripheralDelegate 多播转发

    /// 外设名称更新时广播给所有代理
    public func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        delegateGroup.forEach({ $0.value?.peripheralDidUpdateName?(peripheral) })
    }

    /// 外设服务列表变化时广播给所有代理
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didModifyServices: invalidatedServices) })
    }

    /// 读取 RSSI 完成时广播给所有代理
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didReadRSSI: RSSI, error: error) })
    }

    /// 发现服务完成时广播给所有代理
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didDiscoverServices: error) })
    }

    /// 发现包含服务完成时广播给所有代理
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didDiscoverIncludedServicesFor: service, error: error) })
    }

    /// 发现特征值完成时广播给所有代理
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didDiscoverCharacteristicsFor: service, error: error) })
    }

    /// 描述符值更新时广播给所有代理
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didUpdateValueFor: descriptor, error: error) })
    }

    /// 特征值写入完成时广播给所有代理
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didWriteValueFor: characteristic, error: error) })
    }

    /// 特征值通知订阅状态变化时广播给所有代理
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didUpdateNotificationStateFor: characteristic, error: error) })
    }

    /// 发现特征值描述符完成时广播给所有代理
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didDiscoverDescriptorsFor: characteristic, error: error) })
    }

    /// 特征值数据更新时广播给所有代理（收到通知或读取响应）
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didUpdateValueFor: characteristic, error: error) })
    }

    /// 描述符写入完成时广播给所有代理
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didWriteValueFor: descriptor, error: error) })
    }

    /// 外设准备好接收无响应写入时广播给所有代理
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        delegateGroup.forEach({ $0.value?.peripheralIsReady?(toSendWriteWithoutResponse: peripheral) })
    }

    /// L2CAP 通道打开时广播给所有代理（iOS 11+）
    @available(iOS 11.0, *)
    public func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didOpen: channel, error: error) })
    }
}

/// 用于关联对象存储的 key
private var AssociatedObjectHandle: UInt8 = 0

/// CBPeripheral 的多播代理扩展，通过关联对象为每个外设实例绑定一个 `PeripheralMultiDelegate`。
@objc
public extension CBPeripheral {
    /// 外设的多播代理对象。
    /// 首次访问时自动创建并通过关联对象绑定到当前外设实例，后续访问返回同一对象。
    var multiDelegate: PeripheralMultiDelegate {
        set {
            // 使用 RETAIN_NONATOMIC 策略将多播代理与外设实例绑定
            objc_setAssociatedObject(self, &AssociatedObjectHandle, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        get {
            if let mDelegate = objc_getAssociatedObject(self, &AssociatedObjectHandle) as? PeripheralMultiDelegate {
                // 已存在关联的多播代理，直接返回
                return mDelegate
            } else {
                // 首次访问，创建新的多播代理并绑定
                let mDelegate = PeripheralMultiDelegate()
                self.multiDelegate = mDelegate
                return mDelegate
            }
        }
    }
}

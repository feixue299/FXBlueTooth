//
//  CentralManagerMultiDelegate.swift
//  HTBleManager
//
//  Created by mac on 2021/7/17.
//

import Foundation
import CoreBluetooth

/// 中心管理器多播代理，实现 `CBCentralManagerDelegate` 并将所有回调广播给已注册的多个代理对象。
/// 通过弱引用持有代理，避免循环引用。适用于需要多个模块同时监听蓝牙中心管理器事件的场景。
@objcMembers
open class CentralManagerMultiDelegate: NSObject, CBCentralManagerDelegate {

    /// 已注册的代理弱引用列表
    var delegateGroup: [Weak<CBCentralManagerDelegate>] = []

    /// 注册一个新的代理对象。若该代理已存在则不重复添加。
    /// - Parameter delegate: 需要接收回调的 `CBCentralManagerDelegate` 对象
    public func addDelegate(_ delegate: CBCentralManagerDelegate) {
        if !delegateGroup.contains(where: { $0.value === delegate }) {
            delegateGroup.append(Weak(value: delegate))
        }
    }

    /// 移除已注册的代理对象
    /// - Parameter delegate: 需要移除的 `CBCentralManagerDelegate` 对象
    public func removeDelegate(_ delegate: CBCentralManagerDelegate) {
        guard let index = delegateGroup.firstIndex(where: { $0.value === delegate }) else { return }
        delegateGroup.remove(at: index)
    }

    // MARK: - CBCentralManagerDelegate 多播转发

    /// 蓝牙状态更新时广播给所有代理
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegateGroup.forEach({ $0.value?.centralManagerDidUpdateState(central) })
    }

    /// 状态恢复时广播给所有代理（用于后台恢复场景）
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, willRestoreState: dict) })
    }

    /// 发现外设时广播给所有代理
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI) })
    }

    /// 成功连接外设时广播给所有代理
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, didConnect: peripheral) })
    }

    /// 连接外设失败时广播给所有代理
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, didFailToConnect: peripheral, error: error) })
    }

    /// 外设断开连接时广播给所有代理
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, didDisconnectPeripheral: peripheral, error: error) })
    }

    #if !os(macOS)
    /// 连接事件发生时广播给所有代理（iOS 13+）
    @available(iOS 13.0, *)
    public func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, connectionEventDidOccur: event, for: peripheral) })
    }

    /// ANCS 授权状态更新时广播给所有代理（iOS 13+）
    @available(iOS 13.0, *)
    public func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, didUpdateANCSAuthorizationFor: peripheral) })
    }
    #endif
}

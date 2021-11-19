//
//  CentralManagerMultiDelegate.swift
//  HTBleManager
//
//  Created by mac on 2021/7/17.
//

import Foundation
import CoreBluetooth

@objcMembers
open class CentralManagerMultiDelegate: NSObject, CBCentralManagerDelegate {
    
    var delegateGroup: [Weak<CBCentralManagerDelegate>] = []
    
    public func addDelegate(_ delegate: CBCentralManagerDelegate) {
        if !delegateGroup.contains(where: { $0.value === delegate }) {
            delegateGroup.append(Weak(value: delegate))
        }
    }
    
    public func removeDelegate(_ delegate: CBCentralManagerDelegate) {
        guard let index = delegateGroup.firstIndex(where: { $0.value === delegate }) else { return }
        delegateGroup.remove(at: index)
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegateGroup.forEach({ $0.value?.centralManagerDidUpdateState(central) })
    }
    
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, willRestoreState: dict) })
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI) })
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, didConnect: peripheral) })
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, didFailToConnect: peripheral, error: error) })
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, didDisconnectPeripheral: peripheral, error: error) })
    }
    
    @available(iOS 13.0, *)
    public func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, connectionEventDidOccur: event, for: peripheral) })
    }
    
    @available(iOS 13.0, *)
    public func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        delegateGroup.forEach({ $0.value?.centralManager?(central, didUpdateANCSAuthorizationFor: peripheral) })
    }
}

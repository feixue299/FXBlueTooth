//
//  PeripheralMultiDelegate.swift
//  HTComponents
//
//  Created by mac on 2021/7/3.
//

import Foundation
import CoreBluetooth

@objcMembers
open class PeripheralMultiDelegate: NSObject, CBPeripheralDelegate {
    var delegateGroup: [Weak<CBPeripheralDelegate>] = []
    
    public func addDelegate(_ delegate: CBPeripheralDelegate) {
        if !delegateGroup.contains(where: { $0.value === delegate }) {
            delegateGroup.append(Weak(value: delegate))
        }
    }
    
    public func removeDelegate(_ delegate: CBPeripheralDelegate) {
        guard let index = delegateGroup.firstIndex(where: { $0.value === delegate }) else { return }
        delegateGroup.remove(at: index)
    }
    
    public func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        delegateGroup.forEach({ $0.value?.peripheralDidUpdateName?(peripheral) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didModifyServices: invalidatedServices) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didReadRSSI: RSSI, error: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didDiscoverServices: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didDiscoverIncludedServicesFor: service, error: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didDiscoverCharacteristicsFor: service, error: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didUpdateValueFor: descriptor, error: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didWriteValueFor: characteristic, error: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didUpdateNotificationStateFor: characteristic, error: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didDiscoverDescriptorsFor: characteristic, error: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didUpdateValueFor: characteristic, error: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didWriteValueFor: descriptor, error: error) })
    }
    
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        delegateGroup.forEach({ $0.value?.peripheralIsReady?(toSendWriteWithoutResponse: peripheral) })
    }
    
    @available(iOS 11.0, *)
    public func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        delegateGroup.forEach({ $0.value?.peripheral?(peripheral, didOpen: channel, error: error) })
    }
}

private var AssociatedObjectHandle: UInt8 = 0

@objc
public extension CBPeripheral {
    var multiDelegate: PeripheralMultiDelegate {
        set {
            objc_setAssociatedObject(self, &AssociatedObjectHandle, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        get {
            if let mDelegate = objc_getAssociatedObject(self, &AssociatedObjectHandle) as? PeripheralMultiDelegate {
                return mDelegate
            } else {
                let mDelegate = PeripheralMultiDelegate()
                self.multiDelegate = mDelegate
                return mDelegate
            }
        }
    }
}

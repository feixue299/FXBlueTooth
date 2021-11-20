//
//  CharacteristicAdapter.swift
//  BleManager
//
//  Created by mac on 2021/8/31.
//

import Foundation

public class CharacteristicAdapter: NSObject {
    public typealias ReadyClousre = (PeripheralDevice.DeviceCharacteristicValue) -> Void
    
    public let characteristic: PeripheralDevice.Characteristic
    public let characteristicValue: PeripheralDevice.DeviceCharacteristicValue
    
    private var keyValueObservation: [NSKeyValueObservation] = []
    private var readyForCommand = false {
        didSet {
            if readyForCommand {
                readyForCommandClosureGroup.forEach { closure in
                    closure(characteristicValue)
                }
            }
        }
    }
    private var readyForCommandClosureGroup: [ReadyClousre] = []
    
    public init(characteristic: PeripheralDevice.Characteristic, characteristicValue: PeripheralDevice.DeviceCharacteristicValue) {
        self.characteristic = characteristic
        self.characteristicValue = characteristicValue
        super.init()
        keyValueObservation.append(characteristic.observe(\.readCharacteristic, options: .new) { [weak self] objc, value in
            guard let newValue = value.newValue,
                  let readCharacteristic = newValue,
                  let self = self else { return }
            self.characteristicValue.readCharacteristic = readCharacteristic
            self.characteristicValue.peripheral?.setNotifyValue(true, for: readCharacteristic)
            self.readyForCommand = self.characteristicValue.writeCharacteristic != nil
        })
        keyValueObservation.append(characteristic.observe(\.writeCharacteristic, options: .new, changeHandler: { [weak self] objec, value in
            guard let newValue = value.newValue,
                  let writeCharacteristic = newValue,
                  let self = self else { return }
            self.characteristicValue.writeCharacteristic = writeCharacteristic
            self.readyForCommand = self.characteristicValue.readCharacteristic != nil
        }))
    }
    
    public func readyForCommand(_ closure: @escaping ((PeripheralDevice.DeviceCharacteristicValue) -> Void)) {
        if readyForCommand {
            closure(characteristicValue)
        } else {
            readyForCommandClosureGroup.append(closure)
        }
    }
    
}

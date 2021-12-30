//
//  PeripheralDevice.swift
//  BleManager
//
//  Created by mac on 2021/5/10.
//

import Foundation
import CoreBluetooth

public class PeripheralDevice: NSObject, PeripheralHandler, CBPeripheralDelegate {
    
    private var command: PeripheralCommand?
    
    public var peripheral: CBPeripheral? {
        didSet {
            if let originDelegate = peripheral?.delegate , originDelegate !== peripheral?.multiDelegate {
                peripheral?.delegate = peripheral?.multiDelegate
                peripheral?.multiDelegate.addDelegate(originDelegate)
            } else {
                peripheral?.delegate = peripheral?.multiDelegate
            }
            peripheral?.multiDelegate.addDelegate(self)
        }
    }
    
    public func executable(
        commandItems: [PeripheralCommandItem]? = nil) {
        executable(command: PeripheralCommand(commandItems))
    }
    
    public func executable(
        command: PeripheralCommand? = nil) {
        self.command = command
        peripheral?.discoverServices(command?.discoverServices)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        command?.discoverCharacteristics?.forEach({ $0.didDiscoverCharacteristicsFor(service: service) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        command?.characteristicValues?.forEach({ $0.peripheral(peripheral, didWriteValueFor: characteristic, error: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        command?.characteristicValues?.forEach({ $0.peripheral(peripheral, didUpdateValueFor: characteristic, error: error) })
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        command?.characteristicValues?.forEach({ $0.peripheral(peripheral, didUpdateNotificationStateFor: characteristic, error: error) })
    }
    
}

extension PeripheralDevice {
    
    open class Characteristic: NSObject, DiscoverCharacteristic {
        @objc
        public private(set) dynamic var writeCharacteristic: CBCharacteristic?
        @objc
        public private(set) dynamic var readCharacteristic: CBCharacteristic?
        
        private let writeUUID: CBUUID
        private let readUUID: CBUUID
        
        public init(writeUUID: CBUUID, readUUID: CBUUID) {
            self.writeUUID = writeUUID
            self.readUUID = readUUID
        }
        
        public func didDiscoverCharacteristicsFor(service: CBService) {
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == writeUUID && writeCharacteristic != characteristic {
                    writeCharacteristic = characteristic
                } else if characteristic.uuid == readUUID && readCharacteristic != characteristic {
                    readCharacteristic = characteristic
                }
            }
        }
    }
    
    open class DeviceCharacteristicValue: NSObject, CharacteristicValue {
        public typealias Completion = (Result<[Data], Error>) -> Void
        public typealias SingleCompletion = (Result<Data, Error>) -> Void
        
        public var peripheral: CBPeripheral?
        public var readCharacteristic: CBCharacteristic?
        public var writeCharacteristic: CBCharacteristic?
        private var command: PeripheralOperationCommand?
        private var completion: Completion? {
            didSet {
                if completion != nil {
                    startTimer()
                } else {
                    clearTimer()
                }
            }
        }
        private var dataBuffer: [Data] = []
        private var timeOutTimer: Timer?
        
        
        
        public func executable(option: PeripheralOperationCommand, completion: Completion? = nil) {
            guard let write = writeCharacteristic, let peripheral = peripheral, readCharacteristic != nil else {
                completion?(.failure(NSError.error(description: "未读取到特征值")))
                return
            }
            startTimer()
            
            self.completion = completion
            self.command = option
            dataBuffer.removeAll()
//            bleLogger.debug("发送指令:" + Array(option.cmdData).hexString)
            
            writeData(write, option, peripheral)
        }
        
        private func writeData(_ write: CBCharacteristic, _ option: PeripheralOperationCommand, _ peripheral: CBPeripheral) {
            let length = option.getLengthProtocol()
            
            let type: CBCharacteristicWriteType
            if write.properties.contains(.writeWithoutResponse) {
                type = .withoutResponse
            } else {
                type = .withResponse
            }
            
            
            var data = option.cmdData
            bleLogger.debug("本次指令总长度:\(data.count)")
            while data.count > 0 {
                let sendData: Data
                let currentLength = length.currentLength()
                if data.count >= currentLength {
                    sendData = data.prefix(currentLength)
                    data.removeFirst(currentLength)
                } else {
                    sendData = data
                    data.removeAll()
                }
                bleLogger.debug("count:\(sendData.count) send slice data:\(Array(sendData).hexString)")
                peripheral.writeValue(sendData, for: write, type: type)
            }
        }
        
        public func executable(option: PeripheralOperationCommand, singleCompletion: SingleCompletion? = nil) {
            executable(option: option, completion: { result in
                singleCompletion?(result.map({ $0.reduce(Data(), +) }))
            })
        }
        
        public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
            __handlerValue(error: error)
        }
        
        public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            __handlerValue(error: error)
        }
        
        public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
            __handlerValue(error: error)
        }
        
        private func startTimer() {
            clearTimer()
            timeOutTimer = Timer.scheduledTimer(timeInterval: 20, target: self, selector: #selector(timeout), userInfo: nil, repeats: false)
        }
        
        private func clearTimer() {
            timeOutTimer?.invalidate()
        }
        
        @objc private func timeout() {
            let error = NSError.error(description: "time out")
            __handlerCompletion(.failure(error))
        }
        
        private func __handlerValue(error: Error?) {
            if let error = error {
                __handlerCompletion(.failure(error))
            } else if let value = readCharacteristic?.value {
                __handlerValue(data: value)
            } else {
                bleLogger.info("虚空区域")
            }
        }
        
        private func __handlerValue(data: Data) {
            guard let command = command else { return }
            // 处理和过滤数据
            bleLogger.debug("收到的指令:\(Array(data).hexString)")
            guard let value = command.filterData(data) else { return }
            switch command.checkResponse(dataBuffer, data: value) {
            case .success(let data):
                bleLogger.debug("\(Array(command.cmdData).hexString).指令匹配成功:\(data.map({ Array($0).hexString }))")
                __handlerCompletion(.success(data))
            case .failure(let error):
                __handlerCompletion(.failure(error))
            case .goon(let data):
                dataBuffer = data
                startTimer()
            case .longConnection(let data):
                __handlerCompletion(.success(data), clean: false)
            }
        }
        
        private func __handlerCompletion(_ completion: Result<[Data], Error>, clean: Bool = true) {
            DispatchQueue.main.async {
                self.clearTimer()
                self.completion?(completion)
            }
        }
    }
}

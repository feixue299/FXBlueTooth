//
//  PeripheralDevice.swift
//  BleManager
//
//  Created by mac on 2021/5/10.
//

import Foundation
import CoreBluetooth

/// 外设设备管理器，负责在连接成功后对 `CBPeripheral` 进行服务发现、特征值发现及数据收发的统一管理。
/// 实现 `CBPeripheralDelegate` 并通过多播代理机制将回调分发给各业务处理器。
public class PeripheralDevice: NSObject, PeripheralHandler, CBPeripheralDelegate {

    /// 当前外设操作命令，包含服务发现、特征值发现及数据处理器配置
    private var command: PeripheralCommand?

    /// 关联的蓝牙外设对象。
    /// 赋值时自动配置多播代理：若外设已有代理则将其迁移到多播代理中，并将自身注册为监听者。
    public var peripheral: CBPeripheral? {
        didSet {
            if let originDelegate = peripheral?.delegate, originDelegate !== peripheral?.multiDelegate {
                // 外设已有其他代理，将其迁移到多播代理中，避免覆盖原有代理
                peripheral?.delegate = peripheral?.multiDelegate
                peripheral?.multiDelegate.addDelegate(originDelegate)
            } else {
                // 外设尚无代理或已是多播代理，直接设置
                peripheral?.delegate = peripheral?.multiDelegate
            }
            // 将自身注册到多播代理，接收外设回调
            peripheral?.multiDelegate.addDelegate(self)
        }
    }

    /// 通过命令条目数组启动外设操作（服务发现 → 特征值发现 → 数据交互）
    /// - Parameter commandItems: `PeripheralCommandItem` 数组，传 nil 则发现所有服务
    public func executable(commandItems: [PeripheralCommandItem]? = nil) {
        executable(command: PeripheralCommand(commandItems))
    }

    /// 通过命令结构体启动外设操作
    /// - Parameter command: 包含服务/特征值发现及数据处理器配置的命令，传 nil 则发现所有服务
    public func executable(command: PeripheralCommand? = nil) {
        self.command = command
        // 开始发现服务，传入指定的 Service UUID 列表（nil 表示发现所有服务）
        peripheral?.discoverServices(command?.discoverServices)
    }

    // MARK: - CBPeripheralDelegate

    /// 服务发现完成回调：遍历所有已发现的服务，逐一发起特征值发现
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            // 传 nil 表示发现该服务下的所有特征值
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    /// 特征值发现完成回调：将结果分发给所有已注册的特征值发现处理器
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        command?.discoverCharacteristics?.forEach({ $0.didDiscoverCharacteristicsFor(service: service) })
    }

    /// 特征值写入完成回调：将结果分发给所有已注册的特征值数据处理器
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        command?.characteristicValues?.forEach({ $0.peripheral(peripheral, didWriteValueFor: characteristic, error: error) })
    }

    /// 特征值数据更新回调（收到通知或读取响应）：将数据分发给所有已注册的特征值数据处理器
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        command?.characteristicValues?.forEach({ $0.peripheral(peripheral, didUpdateValueFor: characteristic, error: error) })
    }

    /// 特征值通知订阅状态变化回调：将状态分发给所有已注册的特征值数据处理器
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        command?.characteristicValues?.forEach({ $0.peripheral(peripheral, didUpdateNotificationStateFor: characteristic, error: error) })
    }
}

// MARK: - PeripheralDevice 内嵌类型

extension PeripheralDevice {

    /// 特征值描述类，通过 KVO 动态属性暴露已发现的读写 `CBCharacteristic`，
    /// 供 `CharacteristicAdapter` 监听并同步到 `DeviceCharacteristicValue`。
    open class Characteristic: NSObject, DiscoverCharacteristic {

        /// 已发现的写特征值，使用 @objc dynamic 支持 KVO 监听
        @objc public private(set) dynamic var writeCharacteristic: CBCharacteristic?
        /// 已发现的读特征值，使用 @objc dynamic 支持 KVO 监听
        @objc public private(set) dynamic var readCharacteristic: CBCharacteristic?

        /// 写特征值的 UUID
        private let writeUUID: CBUUID
        /// 读特征值的 UUID
        private let readUUID: CBUUID

        /// 初始化特征值描述
        /// - Parameters:
        ///   - writeUUID: 写特征值的 UUID
        ///   - readUUID: 读特征值的 UUID
        public init(writeUUID: CBUUID, readUUID: CBUUID) {
            self.writeUUID = writeUUID
            self.readUUID = readUUID
        }

        /// 服务特征值发现完成后，从服务的特征值列表中匹配并保存读写特征值
        /// - Parameter service: 已完成特征值发现的 CBService
        public func didDiscoverCharacteristicsFor(service: CBService) {
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == writeUUID && writeCharacteristic != characteristic {
                    // 匹配到写特征值且与当前值不同，更新
                    writeCharacteristic = characteristic
                } else if characteristic.uuid == readUUID && readCharacteristic != characteristic {
                    // 匹配到读特征值且与当前值不同，更新
                    readCharacteristic = characteristic
                }
            }
        }
    }

    /// 特征值数据交互类，负责向外设发送指令、接收响应数据、超时管理及结果回调。
    /// 实现 `CharacteristicValue` 协议，作为外设数据收发的核心执行单元。
    open class DeviceCharacteristicValue: NSObject, CharacteristicValue {

        /// 多包数据完成回调类型，返回数据包数组或错误
        public typealias Completion = (Result<[Data], Error>) -> Void
        /// 单包数据完成回调类型，返回合并后的单个 Data 或错误
        public typealias SingleCompletion = (Result<Data, Error>) -> Void

        /// 关联的蓝牙外设，用于实际的数据写入操作
        public var peripheral: CBPeripheral?
        /// 读特征值，用于接收外设响应数据
        public var readCharacteristic: CBCharacteristic?
        /// 写特征值，用于向外设发送指令数据
        public var writeCharacteristic: CBCharacteristic?

        /// 当前正在执行的操作指令
        private var command: PeripheralOperationCommand?

        /// 当前任务的完成回调，赋值时自动启动超时计时器，置 nil 时停止计时器
        private var completion: Completion? {
            didSet {
                if completion != nil {
                    startTimer()  // 有新任务时启动超时计时
                } else {
                    clearTimer()  // 任务完成或取消时停止计时
                }
            }
        }

        /// 已接收的数据包缓冲区，用于多包数据的累积
        private var dataBuffer: [Data] = []
        /// 超时计时器
        private var timeOutTimer: Timer?

        /// 发送指令并等待多包响应
        /// - Parameters:
        ///   - option: 遵循 `PeripheralOperationCommand` 的操作指令
        ///   - completion: 任务完成回调，返回数据包数组或错误
        public func executable(option: PeripheralOperationCommand, completion: Completion? = nil) {
            guard let write = writeCharacteristic, let peripheral = peripheral, readCharacteristic != nil else {
                // 读写特征值未就绪，直接回调失败
                completion?(.failure(NSError.error(description: "未读取到特征值")))
                return
            }
            startTimer()

            self.completion = completion
            self.command = option
            dataBuffer.removeAll()  // 清空历史缓冲数据，准备接收新响应
//            bleLogger.debug("发送指令:" + Array(option.cmdData).hexString)

            writeData(write, option, peripheral)
        }

        /// 内部方法：将指令数据按分包策略拆分后逐包写入外设
        /// - Parameters:
        ///   - write: 写特征值
        ///   - option: 操作指令（提供数据和分包策略）
        ///   - peripheral: 目标外设
        private func writeData(_ write: CBCharacteristic, _ option: PeripheralOperationCommand, _ peripheral: CBPeripheral) {
            let length = option.getLengthProtocol()

            // 根据特征值属性决定写入类型
            let type: CBCharacteristicWriteType
            if write.properties.contains(.writeWithoutResponse) {
                type = .withoutResponse  // 无响应写入，速度更快
            } else {
                type = .withResponse     // 有响应写入，可靠性更高
            }

            var data = option.cmdData
            bleLogger.debug("本次指令总长度:\(data.count)")

            // 按分包策略循环拆包并逐包发送
            while data.count > 0 {
                let sendData: Data
                let currentLength = length.currentLength()
                if data.count >= currentLength {
                    // 剩余数据超过当前包长度，取前 currentLength 字节
                    sendData = data.prefix(currentLength)
                    data.removeFirst(currentLength)
                } else {
                    // 剩余数据不足一包，全部发送
                    sendData = data
                    data.removeAll()
                }
                bleLogger.debug("count:\(sendData.count) send slice data:\(Array(sendData).hexString)")
                peripheral.writeValue(sendData, for: write, type: type)
            }
        }

        /// 发送指令并等待单包响应（多包数据会自动合并为一个 Data）
        /// - Parameters:
        ///   - option: 遵循 `PeripheralOperationCommand` 的操作指令
        ///   - singleCompletion: 任务完成回调，返回合并后的单个 Data 或错误
        public func executable(option: PeripheralOperationCommand, singleCompletion: SingleCompletion? = nil) {
            executable(option: option, completion: { result in
                // 将多包数据数组合并为单个 Data 后回调
                singleCompletion?(result.map({ $0.reduce(Data(), +) }))
            })
        }

        /// 特征值写入完成回调，转发给内部统一处理方法
        public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
            __handlerValue(error: error)
        }

        /// 特征值数据更新回调（收到外设通知），转发给内部统一处理方法
        public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            __handlerValue(error: error)
        }

        /// 特征值通知订阅状态变化回调，转发给内部统一处理方法
        public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
            __handlerValue(error: error)
        }

        /// 启动或重置超时计时器
        private func startTimer() {
            clearTimer()
            // 使用指令配置的超时时间，默认 20 秒
            timeOutTimer = Timer.scheduledTimer(timeInterval: self.command?.timeOutInterval ?? 20, target: self, selector: #selector(timeout), userInfo: nil, repeats: false)
        }

        /// 停止并销毁超时计时器
        private func clearTimer() {
            timeOutTimer?.invalidate()
        }

        /// 超时回调：构造超时错误并结束当前任务
        @objc private func timeout() {
            let error = NSError.error(description: "time out")
            __handlerCompletion(.failure(error))
        }

        /// 统一处理外设回调：有错误则失败，否则读取特征值数据进行处理
        private func __handlerValue(error: Error?) {
            if let error = error {
                // 回调携带错误，直接结束任务
                __handlerCompletion(.failure(error))
            } else if let value = readCharacteristic?.value {
                // 读取到特征值数据，进行响应校验
                __handlerValue(data: value)
            } else {
                // 无数据也无错误，忽略（等待后续通知）
            }
        }

        /// 处理收到的特征值数据：过滤 → 校验 → 根据结果决定继续等待或完成任务
        private func __handlerValue(data: Data) {
            guard let command = command else { return }
            bleLogger.debug("收到的指令:\(Array(data).hexString)")
            // 先通过 filterData 过滤，返回 nil 表示忽略该数据包
            guard let value = command.filterData(data) else { return }
            switch command.checkResponse(dataBuffer, data: value) {
            case .success(let data):
                // 响应匹配成功，结束任务并回调成功
                bleLogger.debug("\(Array(command.cmdData).hexString).指令匹配成功:\(data.map({ Array($0).hexString }))")
                __handlerCompletion(.success(data))
            case .failure(let error):
                // 响应匹配失败，结束任务并回调错误
                __handlerCompletion(.failure(error))
            case .goon(let data):
                // 数据不完整，更新缓冲区并重置超时计时器，继续等待
                dataBuffer = data
                startTimer()
            case .longConnection(let data):
                // 长连接模式：回调数据但不结束任务（clean: false 保留 completion）
                __handlerCompletion(.success(data), clean: false)
            }
        }

        /// 结束当前任务并在主线程回调结果
        /// - Parameters:
        ///   - completion: 任务结果
        ///   - clean: 是否清空 completion（默认 true，长连接场景传 false 以保持监听）
        private func __handlerCompletion(_ completion: Result<[Data], Error>, clean: Bool = true) {
            DispatchQueue.main.async {
                self.clearTimer()
                self.completion?(completion)
                // clean 为 true 时清空 completion，防止重复回调
            }
        }
    }
}

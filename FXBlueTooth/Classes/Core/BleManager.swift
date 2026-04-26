//
//  BleManager.swift
//  BleManager
//
//  Created by mac on 2021/4/30.
//

import Foundation
import CoreBluetooth
import SwiftyBeaver

/// 全局蓝牙日志记录器，基于 SwiftyBeaver，用于输出调试、错误等级别的蓝牙通信日志。
public let bleLogger = SwiftyBeaver.self

/// 蓝牙管理器错误枚举，描述蓝牙中心管理器在扫描和连接过程中可能出现的各类错误。
public enum BleManagerError: Error {

    /// 中心管理器状态异常的具体原因
    public enum CentralStateReason {
        /// 状态未知
        case unknown
        /// 正在重置
        case resetting
        /// 设备不支持蓝牙
        case unsupported
        /// 应用未获得蓝牙授权
        case unauthorized
        /// 蓝牙已关闭
        case poweredOff
    }

    /// 连接外设失败的具体原因
    public enum CentralConnectReason {
        /// 连接失败，携带底层错误信息
        case failToConnect(Error?)
    }

    /// 中心管理器状态异常错误
    case centralStateError(reason: CentralStateReason)
    /// 连接外设失败错误
    case centralConnectError(reason: CentralConnectReason)
    /// 自定义错误，携带描述字符串
    case custom(String)
}

/// 外设信息模型，封装扫描到的外设对象及其广播数据和信号强度。
public class PeripheralInfo: Equatable {

    /// 蓝牙外设对象
    public let peripheral: CBPeripheral
    /// 外设广播数据字典
    public var advertisementData: [String : Any]
    /// 外设信号强度（RSSI），单位 dBm
    public var rssi: NSNumber?

    /// 初始化外设信息
    /// - Parameters:
    ///   - peripheral: 蓝牙外设对象
    ///   - advertisementData: 外设广播数据
    init(peripheral: CBPeripheral, advertisementData: [String : Any]) {
        self.peripheral = peripheral
        self.advertisementData = advertisementData
    }

    /// 通过外设 UUID 判断两个 PeripheralInfo 是否代表同一外设
    public static func == (lhs: PeripheralInfo, rhs: PeripheralInfo) -> Bool {
        return lhs.peripheral.identifier == rhs.peripheral.identifier
    }
}

/// 蓝牙管理器，提供蓝牙扫描、连接、断开等核心功能的统一入口。
/// 内部通过 `CentralManager` 管理 `CBCentralManager` 的生命周期和事件处理。
public class BleManager {

    /// 操作完成回调类型，成功时携带已连接的 `CBPeripheral`，失败时携带 `BleManagerError`
    public typealias Handler = (Result<CBPeripheral, BleManagerError>) -> Void

    /// 内部中心管理器，负责实际的蓝牙操作
    public let centralManager: CentralManager

    /// 初始化蓝牙管理器
    /// - Parameter options: 传递给 `CBCentralManager` 的初始化选项，如后台恢复标识符等
    public init(options: [String : Any]? = nil) {
        centralManager = CentralManager(options: options)
    }

    /// 通过命令结构体执行蓝牙操作（扫描/连接/断开）
    /// - Parameters:
    ///   - command: 包含扫描、连接等配置的命令，传 nil 则仅触发状态检查
    ///   - handler: 操作完成回调
    public func execute(
        command: BleManagerCommand? = nil,
        handler: Handler? = nil) {
        centralManager.execute(command: command, handler: handler)
    }

    /// 通过命令条目数组执行蓝牙操作
    /// - Parameters:
    ///   - commandItems: `BleManagerCommandItem` 数组，传 nil 则仅触发状态检查
    ///   - handler: 操作完成回调
    public func execute(
        commandItems: [BleManagerCommandItem]? = nil,
        handler: Handler? = nil) {
        centralManager.execute(command: BleManagerCommand(commandItems), handler: handler)
    }
}

public extension BleManager {

    /// 蓝牙中心管理器封装类，实现 `CBCentralManagerDelegate`，
    /// 负责管理扫描、连接、断开等蓝牙操作的完整生命周期。
    class CentralManager: NSObject, CBCentralManagerDelegate {

        /// 底层 CoreBluetooth 中心管理器
        public let centralManager: CBCentralManager
        /// 多播代理，支持多个模块同时监听中心管理器事件
        public let multiDelegate = CentralManagerMultiDelegate()
        /// 当前执行的蓝牙命令
        private var command: BleManagerCommand?
        /// 当前操作的完成回调
        private var handler: Handler?
        /// 本次扫描已发现的外设信息列表
        private var discoverPeripheral: [PeripheralInfo] = []
        /// 状态恢复时系统返回的外设列表（用于后台重连场景）
        public private(set) var restorePeripheral: [CBPeripheral] = []

        /// 初始化中心管理器
        /// - Parameter options: 传递给 `CBCentralManager` 的初始化选项
        init(options: [String : Any]? = nil) {
            // 使用多播代理作为 CBCentralManager 的 delegate，支持多监听者
            centralManager = CBCentralManager(delegate: multiDelegate, queue: nil, options: options)
            super.init()
            // 将自身注册到多播代理，接收中心管理器回调
            multiDelegate.addDelegate(self)
        }

        /// 内部方法：停止扫描并触发完成回调，回调后清空 handler 防止重复触发
        private func handlerComplete(_ completion: Result<CBPeripheral, BleManagerError>) {
            centralManager.stopScan()
            handler?(completion)
            handler = nil
        }

        /// 执行蓝牙操作：停止当前扫描，根据命令配置决定直接连接或重新扫描
        func execute(
            command: BleManagerCommand? = nil,
            handler: Handler? = nil) {

            centralManager.stopScan()
            discoverPeripheral.removeAll()  // 清空上次扫描结果

            self.command = command
            self.handler = handler

            if let cancelConnect = command?.cancelConnect {
                // 命令包含断开连接指令，直接断开指定外设
                centralManager.cancelPeripheralConnection(cancelConnect)
            } else {
                if let connect = command?.connect,
                   let retrieveConnected = command?.retrieveConnected {
                    // 尝试从系统已连接外设列表中检索目标外设（避免重复扫描）
                    if let peripheral = centralManager
                     .retrieveConnectedPeripherals(withServices: retrieveConnected)
                        .first(where: { $0.identifier.uuidString == connect }) {
                        // 在系统已连接列表中找到目标外设，直接发起连接
                        centralManager.connect(peripheral, options: command?.connectInfo)
                    } else if let peripheral = restorePeripheral.first(where: { $0.identifier.uuidString == connect }) {
                        // 在状态恢复列表中找到目标外设，直接发起连接
                        centralManager.connect(peripheral, options: command?.connectInfo)
                    } else {
                        // 未找到已连接外设，触发状态检查以启动扫描流程
                        centralManagerDidUpdateState(centralManager)
                    }
                } else {
                    // 无需检索已连接外设，直接触发状态检查以启动扫描
                    centralManagerDidUpdateState(centralManager)
                }
            }
        }

        // MARK: - CBCentralManagerDelegate

        /// 蓝牙状态更新回调：非就绪状态直接回调失败，就绪时启动扫描
        public func centralManagerDidUpdateState(_ central: CBCentralManager) {
            switch central.state {
            case .unknown:
                handlerComplete(.failure(.centralStateError(reason: .unknown)))
            case .resetting:
                handlerComplete(.failure(.centralStateError(reason: .resetting)))
            case .unsupported:
                handlerComplete(.failure(.centralStateError(reason: .unsupported)))
            case .unauthorized:
                handlerComplete(.failure(.centralStateError(reason: .unauthorized)))
            case .poweredOff:
                handlerComplete(.failure(.centralStateError(reason: .poweredOff)))
            case .poweredOn:
                // 蓝牙已就绪，开始扫描（传入指定 Service UUID 列表，nil 表示扫描所有设备）
                centralManager.scanForPeripherals(withServices: command?.scanServices, options: command?.scanOptions)
            @unknown default:
                break
            }
        }

        /// 状态恢复回调：保存系统恢复的外设列表，用于后续重连
        public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
            guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else { return }
            restorePeripheral = peripherals
        }

        /// 发现外设回调：更新或新增外设信息，触发发现回调，并在找到目标外设时发起连接
        public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
            if let peripheralInfo = discoverPeripheral.first(where: { $0.peripheral == peripheral }) {
                // 已发现过该外设，更新其广播数据和信号强度
                peripheralInfo.advertisementData = advertisementData
                peripheralInfo.rssi = RSSI
            } else {
                // 新发现的外设，创建信息对象
                let info = PeripheralInfo(peripheral: peripheral, advertisementData: advertisementData)
                if let filter = command?.filter {
                    if let peripheralInfo = filter.filter(peripheralInfo: info) {
                        // 通过过滤器筛选，使用过滤器返回的（可能经过修改的）外设信息
                        discoverPeripheral.append(peripheralInfo)
                    }
                } else {
                    // 无过滤器时添加原始信息
                    discoverPeripheral.append(info)
                }
            }

            // 触发外设发现回调，通知业务层更新外设列表
            if let discover = command?.discover {
                discover.discover(peripheralGroup: discoverPeripheral)
            }

            // 若命令指定了目标连接 UUID，且已发现该外设，则立即发起连接
            if let connectuuid = command?.connect,
               let info = discoverPeripheral.first(where: { $0.peripheral.identifier.uuidString == connectuuid }) {
                central.connect(info.peripheral, options: command?.connectInfo)
            }
        }

        /// 连接外设成功回调：回调成功结果，并将外设传递给命令中配置的处理器
        public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            handlerComplete(.success(peripheral))
            // 将已连接外设传递给业务层的 PeripheralHandler（如 PeripheralDevice）
            command?.handle?.peripheral = peripheral
        }

        /// 连接外设失败回调：回调连接失败错误
        public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            handlerComplete(.failure(.centralConnectError(reason: .failToConnect(error))))
        }

        /// 外设断开连接回调：记录日志，通知断开监听器，并回调成功结果
        public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
            bleLogger.debug("断开连接成功:\(peripheral.name ?? "")")
            if let error = error {
                // 异常断开时记录错误日志
                bleLogger.error(error)
            }
            // 通知命令中配置的断开连接监听器
            command?.didDisConnect?.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
            handlerComplete(.success(peripheral))
        }

    }
}

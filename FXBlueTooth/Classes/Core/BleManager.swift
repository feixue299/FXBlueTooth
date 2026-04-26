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

    /// 蓝牙操作成功事件，区分连接成功与断开完成两类语义。
    public enum Event {
        /// 外设连接成功
        case connected(CBPeripheral)
        /// 外设断开完成（主动断开时 error 为 nil，异常断开时携带错误）
        case disconnected(CBPeripheral, error: Error?)
    }

    /// 操作完成回调类型，成功时返回 `Event`，失败时返回 `BleManagerError`
    public typealias Handler = (Result<Event, BleManagerError>) -> Void

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
        /// 当前是否已发起连接（同一轮 execute 内用于防止重复 connect）
        private var connectingPeripheralIdentifier: UUID?
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
        private func handlerComplete(_ completion: Result<Event, BleManagerError>) {
            centralManager.stopScan()
            handler?(completion)
            handler = nil
        }

        /// 统一连接入口：同一轮 execute 中仅允许发起一次连接，避免扫描回调触发重复 connect。
        private func connectIfNeeded(_ peripheral: CBPeripheral, by central: CBCentralManager) {
            guard connectingPeripheralIdentifier == nil else { return }
            connectingPeripheralIdentifier = peripheral.identifier
            central.stopScan()
            central.connect(peripheral, options: command?.connectInfo)
        }

        /// 执行蓝牙操作：停止当前扫描，根据命令配置决定直接连接或重新扫描
        func execute(
            command: BleManagerCommand? = nil,
            handler: Handler? = nil) {

            centralManager.stopScan()
            discoverPeripheral.removeAll()  // 清空上次扫描结果
            connectingPeripheralIdentifier = nil

            self.command = command
            self.handler = handler

            if let cancelConnect = command?.cancelConnect {
                // 命令包含断开连接指令，直接断开指定外设
                centralManager.cancelPeripheralConnection(cancelConnect)
                return
            }

            guard let target = command?.connect else {
                // 无连接目标，仅触发状态检查（纯扫描场景）
                centralManagerDidUpdateState(centralManager)
                return
            }

            switch target {
            case .peripheral(let peripheral):
                // 直接持有外设对象，无需扫描，立即发起连接
                connectIfNeeded(peripheral, by: centralManager)

            case .uuid(let uuid, let retrieveServices):
                // 先尝试从系统已连接列表 / 状态恢复列表中找到外设，避免重复扫描
                if let services = retrieveServices,
                   let peripheral = centralManager
                       .retrieveConnectedPeripherals(withServices: services)
                       .first(where: { $0.identifier.uuidString == uuid }) {
                    connectIfNeeded(peripheral, by: centralManager)
                } else if let peripheral = restorePeripheral
                       .first(where: { $0.identifier.uuidString == uuid }) {
                    connectIfNeeded(peripheral, by: centralManager)
                } else {
                    // 缓存中没有，启动扫描
                    centralManagerDidUpdateState(centralManager)
                }

            case .predicate:
                // 条件匹配需要扫描，启动扫描后在 didDiscover 中自动匹配
                centralManagerDidUpdateState(centralManager)
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

            // 根据连接目标类型决定是否自动发起连接
            guard let target = command?.connect else { return }
            switch target {
            case .uuid(let uuid, _):
                // 按 UUID 匹配：在已发现列表中找到目标外设后立即连接
                if let info = discoverPeripheral.first(where: { $0.peripheral.identifier.uuidString == uuid }) {
                    connectIfNeeded(info.peripheral, by: central)
                }
            case .predicate(let match):
                // 按条件匹配：找到第一个满足条件的外设后立即连接
                if let info = discoverPeripheral.first(where: { match($0) }) {
                    connectIfNeeded(info.peripheral, by: central)
                }
            case .peripheral:
                // 直接传入外设对象的场景不走扫描流程，此处无需处理
                break
            }
        }

        /// 连接外设成功回调：回调成功结果，并将外设传递给命令中配置的处理器
        public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            connectingPeripheralIdentifier = nil
            handlerComplete(.success(.connected(peripheral)))
            // 将已连接外设传递给业务层的 PeripheralHandler（如 PeripheralDevice）
            command?.handle?.peripheral = peripheral
        }

        /// 连接外设失败回调：回调连接失败错误
        public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            connectingPeripheralIdentifier = nil
            handlerComplete(.failure(.centralConnectError(reason: .failToConnect(error))))
        }

        /// 外设断开连接回调：记录日志，通知断开监听器，并回调成功结果
        public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
            connectingPeripheralIdentifier = nil
            bleLogger.debug("断开连接成功:\(peripheral.name ?? "")")
            if let error = error {
                // 异常断开时记录错误日志
                bleLogger.error(error)
            }
            // 通知命令中配置的断开连接监听器
            command?.didDisConnect?.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
            handlerComplete(.success(.disconnected(peripheral, error: error)))
        }

    }
}

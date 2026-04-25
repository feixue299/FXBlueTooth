//
//  BleManagerCommand.swift
//  BleManager
//
//  Created by mac on 2021/4/30.
//

import Foundation
import CoreBluetooth

/// 外设过滤协议，用于在扫描过程中对发现的外设进行筛选。
public protocol PeripheralFilter {
    /// 对发现的外设信息进行过滤
    /// - Parameter peripheralInfo: 扫描到的外设信息
    /// - Returns: 通过过滤的外设信息，返回 nil 表示过滤掉该外设
    func filter(peripheralInfo: PeripheralInfo) -> PeripheralInfo?
}

/// 外设发现回调协议，用于实时接收扫描到的外设列表更新。
public protocol DiscoverPeripheral {
    /// 每次发现新外设或外设信息更新时回调
    /// - Parameter peripheralGroup: 当前已发现的全部外设信息列表
    func discover(peripheralGroup: [PeripheralInfo])
}

/// 外设持有协议，用于在连接成功后将 `CBPeripheral` 传递给业务层。
public protocol PeripheralHandler {
    /// 连接成功的外设对象，由 `BleManager` 在连接成功后自动赋值
    var peripheral: CBPeripheral? { set get }
}

/// 外设断开连接回调协议，用于监听外设断开事件。
public protocol PeripheralDidDisConnect {
    /// 外设断开连接时回调
    /// - Parameters:
    ///   - central: 中心管理器
    ///   - peripheral: 已断开的外设
    ///   - error: 断开原因，主动断开时为 nil，异常断开时携带错误信息
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
}

/// 蓝牙管理器命令条目枚举，以 DSL 风格描述扫描、连接等操作的各项配置。
public enum BleManagerCommandItem {
    /// 扫描时过滤的 Service UUID 列表，传空则扫描所有设备
    case scanServices([CBUUID])
    /// 扫描选项字典，对应 `CBCentralManager.scanForPeripherals` 的 options 参数
    case scanOptions([String: Any])
    /// 外设发现回调处理器
    case discover(DiscoverPeripheral)
    /// 外设过滤器，用于筛选目标外设
    case filter(PeripheralFilter)
    /// 要连接的外设 UUID 字符串
    case connect(uuid: String)
    /// 通过已连接外设列表检索时使用的 Service UUID 列表
    case retrieveConnected(services: [CBUUID])
    /// 连接选项字典，对应 `CBCentralManager.connect` 的 options 参数
    case connectInfo([String : Any])
    /// 连接成功后接收外设对象的处理器
    case handle(PeripheralHandler)
    /// 需要主动断开连接的外设对象
    case cancelConnect(CBPeripheral)
    /// 外设断开连接事件的监听器
    case didDisConnect(PeripheralDidDisConnect)
}

/// 蓝牙管理器命令结构体，聚合一次蓝牙扫描/连接操作所需的全部配置参数。
public struct BleManagerCommand {
    /// 扫描时过滤的 Service UUID 列表
    public var scanServices: [CBUUID]?
    /// 扫描选项
    public var scanOptions: [String: Any]?
    /// 外设发现回调处理器
    public var discover: DiscoverPeripheral?
    /// 外设过滤器
    public var filter: PeripheralFilter?
    /// 目标连接外设的 UUID 字符串
    public var connect: String?
    /// 通过已连接外设列表检索时使用的 Service UUID 列表
    public var retrieveConnected: [CBUUID]?
    /// 连接选项
    public var connectInfo: [String : Any]?
    /// 连接成功后接收外设的处理器
    public var handle: PeripheralHandler?
    /// 需要主动断开的外设对象
    public var cancelConnect: CBPeripheral?
    /// 断开连接事件监听器
    public var didDisConnect: PeripheralDidDisConnect?

    /// 通过命令条目数组初始化，自动解析并填充各字段
    /// - Parameter items: `BleManagerCommandItem` 数组，传 nil 则所有字段保持默认值
    public init(_ items: [BleManagerCommandItem]?) {
        guard let items = items else { return }
        for item in items {
            switch item {
            case .scanServices(let value): scanServices = value
            case .scanOptions(let value): scanOptions = value
            case .discover(let value): discover = value
            case .filter(let value): filter = value
            case .connect(let value): connect = value
            case .connectInfo(let value): connectInfo = value
            case .retrieveConnected(let value): retrieveConnected = value
            case .handle(let value): handle = value
            case .cancelConnect(let value): cancelConnect = value
            case .didDisConnect(let value): didDisConnect = value
            }
        }
    }
}

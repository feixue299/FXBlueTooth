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

/// 连接目标描述，三种方式覆盖所有连接场景。
public enum ConnectTarget {
    /// 按 UUID 字符串连接，适合重连已知设备。
    /// - Parameter uuid: 外设的 identifier.uuidString
    /// - Parameter retrieveServices: 可选，先从系统已连接列表中按此 Service UUID 检索，
    ///   找到则直接连接，避免重复扫描；传 nil 则跳过检索直接扫描。
    case uuid(String, retrieveServices: [CBUUID]? = nil)

    /// 直接传入 `CBPeripheral` 对象连接，适合扫描回调后立即连接。
    case peripheral(CBPeripheral)

    /// 按条件自动匹配，扫描过程中第一个满足条件的外设将被自动连接。
    /// - Parameter predicate: 接收 `PeripheralInfo`，返回 true 表示连接该设备
    case predicate((PeripheralInfo) -> Bool)
}

/// 蓝牙管理器命令条目枚举，以 DSL 风格描述扫描、连接等操作的各项配置。
public enum BleManagerCommandItem {
    /// 扫描时过滤的 Service UUID 列表，传空则扫描所有设备
    case scanServices([CBUUID])
    /// 扫描选项字典，对应 `CBCentralManager.scanForPeripherals` 的 options 参数
    case scanOptions([String: Any])
    /// 外设发现回调处理器
    case discover(DiscoverPeripheral)
    /// 外设过滤器，用于筛选显示在列表中的外设
    case filter(PeripheralFilter)
    /// 连接目标，支持 UUID / CBPeripheral 对象 / 条件匹配三种方式
    case connect(ConnectTarget)
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
    /// 连接目标
    public var connect: ConnectTarget?
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
            case .handle(let value): handle = value
            case .cancelConnect(let value): cancelConnect = value
            case .didDisConnect(let value): didDisConnect = value
            }
        }
    }
}

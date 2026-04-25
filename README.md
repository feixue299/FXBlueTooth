# FXBlueTooth

[![CI Status](https://img.shields.io/travis/feixue299/FXBlueTooth.svg?style=flat)](https://travis-ci.org/feixue299/FXBlueTooth)
[![Version](https://img.shields.io/cocoapods/v/FXBlueTooth.svg?style=flat)](https://cocoapods.org/pods/FXBlueTooth)
[![License](https://img.shields.io/cocoapods/l/FXBlueTooth.svg?style=flat)](https://cocoapods.org/pods/FXBlueTooth)
[![Platform](https://img.shields.io/cocoapods/p/FXBlueTooth.svg?style=flat)](https://cocoapods.org/pods/FXBlueTooth)

基于 CoreBluetooth 封装的 iOS 蓝牙管理库，提供扫描、连接、特征值读写等完整流程的链式调用接口。

## 功能特性

- 扫描外设，支持自定义过滤规则
- 连接 / 断开外设
- 服务与特征值自动发现
- 分包发送指令，自动处理 MTU 限制
- 响应数据校验与超时处理
- 多代理（MultiDelegate）支持，不破坏原有 delegate 链

## 要求

- iOS 10.0+
- Swift 5.0+
- Xcode 12+

## 集成方式

### CocoaPods

在 `Podfile` 中添加：

```ruby
pod 'FXBlueTooth'
```

然后执行：

```bash
pod install
```

### Swift Package Manager

在 `Package.swift` 的 `dependencies` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/feixue299/FXBlueTooth.git", from: "0.4.0")
]
```

或在 Xcode 中选择 **File → Add Packages**，输入仓库地址：

```
https://github.com/feixue299/FXBlueTooth.git
```

### 手动集成

克隆仓库后，将 `FXBlueTooth/Classes` 目录下的所有文件拖入项目即可。

## 使用示例

### 1. 初始化 BleManager

```swift
import FXBlueTooth

let bleManager = BleManager()
```

如需开启状态恢复（State Restoration），可传入 options：

```swift
let bleManager = BleManager(options: [
    CBCentralManagerOptionRestoreIdentifierKey: "com.yourapp.ble"
])
```

---

### 2. 扫描并连接外设

#### 扫描所有外设

```swift
bleManager.execute(
    commandItems: [
        .discover(myDiscoverHandler)   // 实现 DiscoverPeripheral 协议
    ]
) { result in
    switch result {
    case .success(let peripheral):
        print("已连接：\(peripheral.name ?? "未知设备")")
    case .failure(let error):
        print("错误：\(error)")
    }
}
```

#### 按服务 UUID 过滤扫描，并自动连接指定设备

```swift
let targetUUID = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"

bleManager.execute(
    commandItems: [
        .scanServices([CBUUID(string: "FFE0")]),
        .filter(myFilter),                        // 实现 PeripheralFilter 协议
        .connect(uuid: targetUUID),
        .handle(peripheralDevice)                 // 连接成功后绑定 PeripheralDevice
    ]
) { result in
    switch result {
    case .success(let peripheral):
        print("连接成功：\(peripheral.name ?? "")")
    case .failure(let error):
        print("连接失败：\(error)")
    }
}
```

#### 自定义过滤器示例

```swift
class MyFilter: PeripheralFilter {
    func filter(peripheralInfo: PeripheralInfo) -> PeripheralInfo? {
        // 只保留名称包含 "MyDevice" 的外设
        guard peripheralInfo.peripheral.name?.contains("MyDevice") == true else {
            return nil
        }
        return peripheralInfo
    }
}
```

#### 监听扫描结果示例

```swift
class MyDiscoverHandler: DiscoverPeripheral {
    func discover(peripheralGroup: [PeripheralInfo]) {
        for info in peripheralGroup {
            print("发现设备：\(info.peripheral.name ?? "未知"), RSSI: \(info.rssi ?? 0)")
        }
    }
}
```

---

### 3. 断开连接

```swift
bleManager.execute(
    commandItems: [
        .cancelConnect(peripheral)
    ]
)
```

---

### 4. 发现服务与特征值

连接成功后，使用 `PeripheralDevice` 发现服务和特征值：

```swift
let peripheralDevice = PeripheralDevice()

// 定义读写特征值
let characteristic = PeripheralDevice.Characteristic(
    writeUUID: CBUUID(string: "FFE1"),
    readUUID:  CBUUID(string: "FFE2")
)

peripheralDevice.executable(commandItems: [
    .discoverServices([CBUUID(string: "FFE0")]),
    .discoverCharacteristics([characteristic]),
    .characteristicValues([deviceCharacteristicValue])
])
```

---

### 5. 发送指令并接收响应

实现 `PeripheralOperationCommand` 协议定义一条指令：

```swift
struct QueryStatusCommand: PeripheralOperationCommand {

    // 要发送的原始数据
    var cmdData: Data {
        return Data([0xAA, 0x01, 0x00, 0xFF])
    }

    // 过滤收到的数据（返回 nil 则忽略该包）
    func filterData(_ data: Data) -> Data? {
        guard data.first == 0xAA else { return nil }
        return data
    }

    // 校验响应是否完整
    func checkResponse(_ dataGroup: [Data], data: Data) -> CheckResponseResult {
        // 单包响应直接返回成功
        return .success([data])
    }

    // 超时时间（默认 20s）
    var timeOutInterval: TimeInterval { return 10 }
}
```

发送指令：

```swift
let characteristicValue = PeripheralDevice.DeviceCharacteristicValue()
characteristicValue.peripheral         = peripheral
characteristicValue.writeCharacteristic = characteristic.writeCharacteristic
characteristicValue.readCharacteristic  = characteristic.readCharacteristic

characteristicValue.executable(
    option: QueryStatusCommand(),
    singleCompletion: { result in
        switch result {
        case .success(let data):
            print("收到响应：\(Array(data).map { String(format: "%02X", $0) }.joined(separator: " "))")
        case .failure(let error):
            print("指令失败：\(error)")
        }
    }
)
```

---

### 6. 监听断开连接

```swift
class MyDisconnectHandler: PeripheralDidDisConnect {
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("设备断开：\(peripheral.name ?? ""), error: \(String(describing: error))")
        // 在此处理重连逻辑
    }
}

bleManager.execute(
    commandItems: [
        .connect(uuid: targetUUID),
        .didDisConnect(MyDisconnectHandler())
    ]
) { _ in }
```

---

### 综合示例：完整使用流程

下面的 `BlueToothManager` 把扫描、过滤、连接、特征值发现、指令收发、断连重连、长连接通知等所有功能整合在一起，可直接作为项目中蓝牙模块的起点。

```swift
import UIKit
import CoreBluetooth
import FXBlueTooth

// MARK: - 1. 定义指令（单包响应）

struct QueryStatusCommand: PeripheralOperationCommand {

    var cmdData: Data { Data([0xAA, 0x01, 0x00, 0xFF]) }

    // 过滤：只处理以 0xAA 开头的包
    func filterData(_ data: Data) -> Data? {
        data.first == 0xAA ? data : nil
    }

    // 单包即完整响应
    func checkResponse(_ dataGroup: [Data], data: Data) -> CheckResponseResult {
        .success(data: [data])
    }

    var timeOutInterval: TimeInterval { 10 }
}

// MARK: - 2. 定义多包响应指令（需要拼包）

struct LongDataCommand: PeripheralOperationCommand {

    var cmdData: Data { Data([0xBB, 0x02, 0x00, 0xFF]) }

    func filterData(_ data: Data) -> Data? {
        data.first == 0xBB ? data : nil
    }

    // 收到 3 包后才算完整
    func checkResponse(_ dataGroup: [Data], data: Data) -> CheckResponseResult {
        var buffer = dataGroup
        buffer.append(data)
        if buffer.count >= 3 {
            return .success(data: buffer)
        }
        return .goon(data: buffer)
    }

    // 自定义分包长度：首包 20 字节，后续 512 字节
    func getLengthProtocol() -> PeripheralCommandLengthProtocol {
        FirstPeripheralCommandLength(first: 20, then: 512)
    }
}

// MARK: - 3. 定义长连接指令（持续推送，不自动结束）

struct NotifyCommand: PeripheralOperationCommand {

    var cmdData: Data { Data([0xCC, 0x03, 0x00, 0xFF]) }

    func filterData(_ data: Data) -> Data? {
        data.first == 0xCC ? data : nil
    }

    func checkResponse(_ dataGroup: [Data], data: Data) -> CheckResponseResult {
        // 每次收到数据都回调，不结束监听
        .longConnection(data: [data])
    }
}

// MARK: - 4. 设备过滤器

class DeviceFilter: PeripheralFilter {
    func filter(peripheralInfo: PeripheralInfo) -> PeripheralInfo? {
        guard peripheralInfo.peripheral.name?.hasPrefix("MyDevice") == true else { return nil }
        return peripheralInfo
    }
}

// MARK: - 5. 扫描结果回调

class DeviceDiscoverer: DiscoverPeripheral {
    var onDiscover: (([PeripheralInfo]) -> Void)?
    func discover(peripheralGroup: [PeripheralInfo]) {
        onDiscover?(peripheralGroup)
    }
}

// MARK: - 6. 断连处理

class DisconnectHandler: PeripheralDidDisConnect {
    var onDisconnect: ((CBPeripheral, Error?) -> Void)?
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        onDisconnect?(peripheral, error)
    }
}

// MARK: - 7. 整合管理类

class BlueToothManager {

    // --- 核心对象 ---
    private let bleManager    = BleManager()
    private let peripheralDevice = PeripheralDevice()

    // --- 特征值 ---
    private let characteristic = PeripheralDevice.Characteristic(
        writeUUID: CBUUID(string: "FFE1"),
        readUUID:  CBUUID(string: "FFE2")
    )
    private let characteristicValue = PeripheralDevice.DeviceCharacteristicValue()

    // CharacteristicAdapter：自动绑定读写特征值，并在就绪后回调
    private lazy var adapter = CharacteristicAdapter(
        characteristic: characteristic,
        characteristicValue: characteristicValue
    )

    // --- 辅助对象 ---
    private let discoverer        = DeviceDiscoverer()
    private let disconnectHandler = DisconnectHandler()
    private let filter            = DeviceFilter()

    private var targetUUID: String?

    // MARK: 启动扫描

    func startScan() {
        discoverer.onDiscover = { infos in
            print("扫描到 \(infos.count) 台设备")
            infos.forEach { print("  - \($0.peripheral.name ?? "未知"), RSSI: \($0.rssi ?? 0)") }
        }

        bleManager.execute(
            commandItems: [
                .scanServices([CBUUID(string: "FFE0")]),   // 按服务 UUID 过滤扫描
                .discover(discoverer),                      // 扫描结果回调
                .filter(filter)                             // 只保留名称匹配的设备
            ]
        ) { [weak self] result in
            if case .failure(let error) = result {
                print("扫描错误：\(error)")
            }
        }
    }

    // MARK: 连接指定设备

    func connect(uuid: String) {
        targetUUID = uuid

        disconnectHandler.onDisconnect = { [weak self] peripheral, error in
            print("断开连接：\(peripheral.name ?? ""), error: \(String(describing: error))")
            // 自动重连
            if let uuid = self?.targetUUID {
                self?.connect(uuid: uuid)
            }
        }

        // 绑定 peripheralDevice，连接成功后自动发现服务
        peripheralDevice.executable(commandItems: [
            .discoverServices([CBUUID(string: "FFE0")]),
            .discoverCharacteristics([characteristic]),
            .characteristicValues([characteristicValue])
        ])

        bleManager.execute(
            commandItems: [
                .scanServices([CBUUID(string: "FFE0")]),
                .filter(filter),
                .connect(uuid: uuid),
                // 先尝试从已连接列表中恢复，避免重复扫描
                .retrieveConnected(services: [CBUUID(string: "FFE0")]),
                .handle(peripheralDevice),
                .didDisConnect(disconnectHandler)
            ]
        ) { [weak self] result in
            switch result {
            case .success(let peripheral):
                print("连接成功：\(peripheral.name ?? "")")
                // 等待特征值就绪后再发送指令
                self?.characteristicValue.peripheral = peripheral
                self?.adapter.readyForCommand { cv in
                    print("特征值就绪，可以发送指令")
                    self?.sendQueryStatus()
                }
            case .failure(let error):
                print("连接失败：\(error)")
            }
        }
    }

    // MARK: 断开连接

    func disconnect(peripheral: CBPeripheral) {
        targetUUID = nil   // 清除目标，禁止自动重连
        bleManager.execute(commandItems: [.cancelConnect(peripheral)])
    }

    // MARK: 发送单包指令

    func sendQueryStatus() {
        adapter.readyForCommand { cv in
            cv.executable(option: QueryStatusCommand(), singleCompletion: { result in
                switch result {
                case .success(let data):
                    let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                    print("QueryStatus 响应：\(hex)")
                case .failure(let error):
                    print("QueryStatus 失败：\(error)")
                }
            })
        }
    }

    // MARK: 发送多包指令（自动拼包）

    func sendLongData() {
        adapter.readyForCommand { cv in
            cv.executable(option: LongDataCommand()) { result in
                switch result {
                case .success(let packets):
                    print("LongData 收到 \(packets.count) 包")
                case .failure(let error):
                    print("LongData 失败：\(error)")
                }
            }
        }
    }

    // MARK: 开启长连接通知（持续接收推送）

    func startNotify() {
        adapter.readyForCommand { cv in
            cv.executable(option: NotifyCommand()) { result in
                if case .success(let packets) = result {
                    let hex = packets.first.map { Array($0).map { String(format: "%02X", $0) }.joined(separator: " ") } ?? ""
                    print("Notify 推送：\(hex)")
                }
            }
        }
    }

    // MARK: 使用 BlueToothTaskModel 封装业务任务

    func buildStatusTask(onResult: @escaping (String) -> Void) -> BlueToothTaskModel<String> {
        let task = BlueToothTaskModel<String>(
            command: QueryStatusCommand(),
            parse: .value2({ data in
                // 将原始 Data 解析为业务字符串
                data.map { String(format: "%02X", $0) }.joined(separator: " ")
            }),
            plugins: [onResult]
        )
        return task
    }
}
```

**使用方式：**

```swift
let btManager = BlueToothManager()

// 扫描
btManager.startScan()

// 连接（UUID 从扫描结果中获取）
btManager.connect(uuid: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX")

// 连接成功后，指令发送由 adapter.readyForCommand 回调自动触发
// 也可以手动调用：
btManager.sendQueryStatus()
btManager.sendLongData()
btManager.startNotify()
```

---

## 运行示例项目

```bash
git clone https://github.com/feixue299/FXBlueTooth.git
cd FXBlueTooth/Example
pod install
open FXBlueTooth.xcworkspace
```

## 作者

feixue299 — ariablink299@gmail.com

## License

FXBlueTooth is available under the MIT license. See the LICENSE file for more info.

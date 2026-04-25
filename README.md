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

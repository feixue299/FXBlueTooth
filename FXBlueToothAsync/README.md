# FXBlueToothAsync

支持 Swift 5.5+ async/await 的蓝牙库。纯 CoreBluetooth 封装，零依赖。

## 基础 API

```swift
let manager = AsyncBleManager()

// 获取蓝牙状态
let state = try await manager.getState()

// 扫描并连接 (闭包返回 ScanAction)
let device = try await manager.scan() { discovered in
    if discovered.peripheral.name == "MyDevice" {
        return .connect  // 连接这个设备，停止扫描
    }
    return .skip  // 跳过，继续扫描
}

// 在已连接设备上操作
let services = try await device.discover(serviceUUIDs: [...])
let characteristics = try await device.discover(characteristicUUIDs: [...], for: service)
let data = try await device.read(for: characteristic)
try await device.write(data, to: characteristic)

let notifications = device.notifications(for: characteristic)
for try await data in notifications {
    print("通知: \(data)")
}

// 断开连接
try await manager.disconnect(device.peripheral)
```

## 完整流程示例

```swift
let manager = AsyncBleManager()

// 1. 扫描并连接到目标设备
let device = try await manager.scan() { discovered in
    if discovered.peripheral.name == "MyBleDevice" {
        return .connect  // 连接这个设备，停止扫描
    }
    return .skip  // 不是目标，继续扫描
}

// 2. 发现服务
let services = try await device.discover(serviceUUIDs: nil)
let targetService = services.first!

// 3. 发现特性
let characteristics = try await device.discover(
    characteristicUUIDs: nil,
    for: targetService
)

// 4. 读取特性值
if let readChar = characteristics.first(where: { $0.properties.contains(.read) }) {
    let data = try await device.read(for: readChar, timeout: 5)
    print("读到: \(data)")
}

// 5. 写入数据
if let writeChar = characteristics.first(where: { $0.properties.contains(.write) }) {
    let writeData = "Hello".data(using: .utf8)!
    try await device.write(writeData, to: writeChar, type: .withResponse)
}

// 6. 监听通知
if let notifyChar = characteristics.first(where: { $0.properties.contains(.notify) }) {
    let stream = device.notifications(for: notifyChar)
    for try await data in stream {
        print("通知数据: \(data)")
    }
}

// 7. 断开连接
try await manager.disconnect(device.peripheral)
```

## API 说明

### AsyncBleManager

| 方法 | 说明 |
|------|------|
| `getState()` | 获取蓝牙状态 |
| `scan(onDiscovered:)` | 扫描设备，闭包返回 ScanAction (.skip 继续扫描，.connect 连接并停止) |
| `connect(_ discovered)` | 连接发现的设备 |
| `connect(_ peripheral)` | 连接指定 peripheral |
| `disconnect(_ peripheral)` | 断开连接 |
| `connectionEvents()` | 监听连接/断开事件流 |
| `stopScan()` | 停止扫描 |

### AsyncPeripheral (已连接设备)

| 方法 | 说明 |
|------|------|
| `discover(serviceUUIDs:, timeout:)` | 发现服务 |
| `discover(characteristicUUIDs:for:, timeout:)` | 发现特性 |
| `read(for:, timeout:)` | 读取特性值 |
| `write(_:to:type:, timeout:)` | 写入数据 |
| `notifications(for:, bufferingPolicy:)` | 订阅通知流 |

## 超时和取消

所有 I/O 操作都支持超时和 Task 取消：

```swift
// 指定超时
let services = try await device.discover(timeout: 10)

// Task 取消支持
let task = Task {
    let device = try await manager.scan() { discovered in
        if discovered.peripheral.name == "MyDevice" {
            try await manager.connect(discovered)
        }
    }
}

task.cancel()  // 取消扫描
```

## 错误处理

```swift
do {
    try await manager.getState()
} catch AsyncBleClientError.bluetoothUnavailable(let state) {
    print("蓝牙不可用: \(state)")
} catch AsyncBleClientError.timeout {
    print("操作超时")
} catch AsyncBleClientError.busy {
    print("设备忙碌")
} catch {
    print("其他错误: \(error)")
}
```

## 类型定义

### AsyncDiscoveredPeripheral
扫描发现的设备信息

```swift
struct AsyncDiscoveredPeripheral {
    let peripheral: CBPeripheral
    let advertisementData: [String: Any]
    let rssi: NSNumber
}
```

### AsyncPeripheral
已连接的设备对象，提供所有 I/O 操作（discover、read、write、notifications）

### ScanAction
扫描闭包的返回值，用于控制扫描流程：
- `.skip` - 跳过当前设备，继续扫描
- `.connect` - 连接该设备，停止扫描

### AsyncBleClientError
统一的错误类型：
- `bluetoothUnavailable(CBManagerState)`
- `busy`
- `timeout`
- `peripheralNotFound(UUID)`
- `connectFailed(CBPeripheral, Error?)`
- `operationFailed(Operation, Error)`

## 平台支持

- iOS 13.0+
- macOS 10.15+
- watchOS 6.0+
- tvOS 13.0+

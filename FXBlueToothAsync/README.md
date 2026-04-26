# FXBlueToothAsync - Swift 并发风格 BLE 库

支持 Swift 5.5+ async/await 的蓝牙库。底层使用纯 CoreBluetooth，设计独立，零依赖。

## 设计原则

- **基础操作优先** - 提供细粒度的单一功能（getState、scan、connect、discover），用户自行组合
- **Async/Await 原生** - 所有操作都使用 async/await，支持 Task 取消
- **类型安全** - 返回特定类型（AsyncConnectedPeripheral）保证链式调用
- **错误明确** - 统一的 AsyncBleClientError，支持 LocalizedError

## 快速开始

### 1. 获取蓝牙状态

```swift
let manager = AsyncBleManager()
let state = try await manager.getState()  // -> CBManagerState
print("蓝牙状态: \(state)")
```

### 2. 扫描设备

```swift
let request = AsyncScanRequest()  // 默认配置

let scanStream = manager.scan(request)
for try await discovered in scanStream {
    print("发现设备: \(discovered.peripheral.name ?? "Unknown")")
    
    // 在循环内部可以连接设备
    if discovered.peripheral.name?.contains("Target") == true {
        let connected = try await manager.connect(discovered)
        break  // 退出扫描循环
    }
}
```

### 3. 连接设备

```swift
// 从扫描结果中连接
let discovered: AsyncDiscoveredPeripheral = ...
let connected = try await manager.connect(discovered, timeout: 15)

// 或直接连接已知的 peripheral
let peripheral: CBPeripheral = ...
let connected = try await manager.connect(peripheral, timeout: 15)
```

**返回值：** `AsyncConnectedPeripheral` - 已连接的设备对象，提供后续 I/O 操作

### 4. 发现服务

```swift
let connected: AsyncConnectedPeripheral = ...

// 发现所有服务
let services = try await connected.discoverServices()

// 或指定 UUID 列表
let serviceUUIDs = [CBUUID(string: "180A")]
let services = try await connected.discoverServices(serviceUUIDs, timeout: 10)
```

### 5. 发现特性

```swift
let service = services[0]

// 发现所有特性
let characteristics = try await connected.discoverCharacteristics(for: service)

// 或指定 UUID 列表
let charUUIDs = [CBUUID(string: "2A29")]
let characteristics = try await connected.discoverCharacteristics(charUUIDs, for: service, timeout: 10)
```

### 6. 读取数据

```swift
let characteristic: CBCharacteristic = ...

let data = try await connected.readValue(for: characteristic, timeout: 10)
print("读取数据: \(data.hexString)")
```

### 7. 写入数据

```swift
let data = "Hello".data(using: .utf8)!

// 带应答的写入
try await connected.write(data, to: characteristic, type: .withResponse, timeout: 10)

// 不带应答的写入（更快）
try await connected.write(data, to: characteristic, type: .withoutResponse)
```

### 8. 订阅通知

```swift
let characteristic: CBCharacteristic = ...

let notificationStream = connected.notifications(
    for: characteristic,
    bufferingPolicy: .unbounded  // 可选：.bufferingNewest(10) 限制缓冲
)

for try await data in notificationStream {
    print("收到通知: \(data.hexString)")
}
```

### 9. 断开连接

```swift
try await manager.disconnect(connected.peripheral)
```

### 10. 监听连接事件

```swift
let eventStream = manager.connectionEvents()

Task {
    for await event in eventStream {
        switch event {
        case .connected(let peripheral):
            print("已连接: \(peripheral.name ?? "Unknown")")
        case .disconnected(let peripheral, let error):
            print("已断开: \(error?.localizedDescription ?? "主动断开")")
        }
    }
}
```

## 完整示例

```swift
import FXBlueToothAsync
import CoreBluetooth

let manager = AsyncBleManager()

// 1. 获取状态
let state = try await manager.getState()
guard state == .poweredOn else { throw BleError.notAvailable }

// 2. 扫描
let scanStream = manager.scan(AsyncScanRequest())
var targetPeripheral: AsyncDiscoveredPeripheral?

// 3. 在扫描中寻找目标设备
for try await discovered in scanStream {
    if discovered.peripheral.name == "MyDevice" {
        targetPeripheral = discovered
        break
    }
}

guard let target = targetPeripheral else { throw BleError.notFound }

// 4. 连接
let connected = try await manager.connect(target, timeout: 15)
print("已连接: \(connected.peripheral.name ?? "Unknown")")

// 5. 发现服务和特性
let services = try await connected.discoverServices()
let service = services[0]
let characteristics = try await connected.discoverCharacteristics(for: service)

// 6. 读写操作
if let readChar = characteristics.first(where: { $0.uuid.uuidString == "2A29" }) {
    let data = try await connected.readValue(for: readChar, timeout: 5)
    print("读到数据: \(data)")
}

// 7. 简化流程 - 写入数据
let writeData = "Hello".data(using: .utf8)!
if let writeChar = characteristics.first(where: { $0.properties.contains(.write) }) {
    try await connected.write(writeData, to: writeChar, type: .withResponse, timeout: 10)
}

// 8. 监听通知
if let notifyChar = characteristics.first(where: { $0.properties.contains(.notify) }) {
    let notificationStream = connected.notifications(for: notifyChar)
    
    Task {
        for try await notifData in notificationStream {
            print("通知: \(notifData)")
        }
    }
}

// 9. 断开
try await manager.disconnect(connected.peripheral)
```

## 超时参数

所有 I/O 操作都支持可选的 `timeout` 参数：

```swift
// 10 秒超时
let services = try await connected.discoverServices(timeout: 10)

// 无超时（使用 nil 或省略）
let characteristics = try await connected.discoverCharacteristics(for: service)
```

## 缓冲策略

通知流支持不同的缓冲策略：

```swift
// 无缓冲限制（默认）
let stream1 = connected.notifications(for: char, bufferingPolicy: .unbounded)

// 限制缓冲大小为 10
let stream2 = connected.notifications(
    for: char,
    bufferingPolicy: .bufferingNewest(10)
)
```

## 错误处理

统一的错误类型 `AsyncBleClientError`：

```swift
do {
    try await manager.getState()
} catch AsyncBleClientError.bluetoothUnavailable(let state) {
    print("蓝牙不可用: \(state)")
} catch AsyncBleClientError.timeout {
    print("操作超时")
} catch AsyncBleClientError.busy {
    print("设备忙碌")
} catch AsyncBleClientError.operationFailed(let operation, let error) {
    print("操作失败: \(operation) - \(error.localizedDescription)")
}
```

## Task 取消

所有操作都支持 Swift Concurrency 的 Task 取消：

```swift
let task = Task {
    let scanStream = manager.scan(AsyncScanRequest())
    for try await discovered in scanStream {
        // ...
    }
}

// 在某个时刻取消
task.cancel()
```

## 类型定义

### AsyncDiscoveredPeripheral
```swift
struct AsyncDiscoveredPeripheral {
    let peripheral: CBPeripheral
    let advertisementData: [String: Any]
    let rssi: NSNumber
}
```

### AsyncConnectedPeripheral
在成功连接后获得，提供以下方法：
- `discoverServices(_:timeout:)`
- `discoverCharacteristics(_:for:timeout:)`
- `readValue(for:timeout:)`
- `write(_:to:type:timeout:)`
- `notifications(for:bufferingPolicy:)`

### AsyncBleClientError
```swift
enum AsyncBleClientError: Error {
    case bluetoothUnavailable(CBManagerState)
    case busy
    case timeout
    case peripheralNotFound(UUID)
    case invalidState(String)
    case connectFailed(CBPeripheral, Error?)
    case operationFailed(Operation, Error)
}
```

## 平台支持

- iOS 13.0+
- macOS 10.15+
- watchOS 6.0+
- tvOS 13.0+

## 许可证

MIT License

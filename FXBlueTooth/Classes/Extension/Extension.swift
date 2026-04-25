//
//  Extension.swift
//  BleManager
//
//  Created by mac on 2021/5/10.
//

import Foundation

// MARK: - 整数大端字节序扩展

/// 固定宽度整数的大端字节序扩展
extension FixedWidthInteger {
    /// 将整数转换为大端字节序的 UInt8 数组
    /// 例：Int16(0x0102).bigEndianBytes == [0x01, 0x02]
    public var bigEndianBytes: [UInt8] {
        [UInt8](withUnsafeBytes(of: self.bigEndian) { Data($0) })
    }
}

/// 二进制浮点数的大端字节序扩展
/// 注意：遵循 IEEE 754-2008 标准，若目标系统使用不同浮点表示需自行适配
// `BinaryFloatingPoint` conforms to 754-2008 - IEEE Standard for Floating-Point Arithmetic (https://ieeexplore.ieee.org/document/4610935)
// If you target system is using a different floating point representation, you need to adapt accordingly
extension BinaryFloatingPoint {
    /// 将浮点数转换为大端字节序的 UInt8 数组（字节顺序已反转）
    public var bigEndianBytes: [UInt8] {
        [UInt8](withUnsafeBytes(of: self) { Data($0) }).reversed()
    }
}

// MARK: - Data 扩展

/// Data 的常用扩展方法集合
public extension Data {

    /// 将 Data 转换为 UInt8 元素数组
    var array: Array<Element> {
        return Array(self)
    }

    /// 将 Data 按低高字节顺序转换为 Int（小端序）
    ///
    /// 示例：
    /// ```swift
    /// let bytes = Data([0x01, 0x02])
    /// bytes.toInt() // 513
    /// ```
    func toInt() -> Int {
        var num: Int = 0
        let data = NSData(data: self)
        data.getBytes(&num, length: MemoryLayout<Int>.size)
        return num
    }

    /// 将字节数组两两配对转换为 UInt16 数组（大端序）
    ///
    /// 要求字节数为偶数，否则返回 nil。
    ///
    /// 示例：
    /// ```swift
    /// let byteArr: [UInt8] = [255, 255, 0, 255, 255, 0, 104, 76]
    /// Data(byteArr).byteArrToUInt16() // [65535, 255, 65280, 26700]
    /// ```
    /// - Returns: UInt16 数组，字节数为奇数时返回 nil
    func byteArrToUInt16() -> [UInt16]? {
        let byteArr = array
        let numBytes = byteArr.count
        var byteArrSlice = byteArr[0..<numBytes]

        // 字节数必须为偶数，否则无法完整配对
        guard numBytes % 2 == 0 else { return nil }

        var arr: [UInt16] = Array(repeating: 0, count: numBytes / 2)

        // 从后向前逐对合并字节为 UInt16（高字节 << 8 | 低字节）
        for i in (0..<numBytes / 2).reversed() {
            arr[i] = UInt16(byteArrSlice.removeLast()) +
                     UInt16(byteArrSlice.removeLast()) << 8
        }
        return arr
    }

    /// 将字节数组每四字节配对转换为 UInt32 数组（大端序）
    ///
    /// 要求字节数为 4 的倍数，否则返回 nil。
    /// - Returns: UInt32 数组，字节数不是 4 的倍数时返回 nil
    func byteArrToUInt32() -> [UInt32]? {
        let byteArr = array
        let numBytes = byteArr.count
        var byteArrSlice = byteArr[0..<numBytes]

        // 字节数必须为 4 的倍数
        guard numBytes % 4 == 0 else { return nil }

        var arr: [UInt32] = Array(repeating: 0, count: numBytes / 4)

        // 从后向前逐四字节合并为 UInt32
        for i in (0..<numBytes / 4).reversed() {
            arr[i] = UInt32(byteArrSlice.removeLast()) +
                UInt32(byteArrSlice.removeLast()) << 8 +
                UInt32(byteArrSlice.removeLast()) << 16 +
                UInt32(byteArrSlice.removeLast()) << 24
        }
        return arr
    }

    /// 将 Data 解析为 Float 值（小端序，IEEE 754 单精度浮点）
    /// - Returns: 对应的 Float 值
    func floatValue() -> Float {
        return Float(bitPattern: UInt32(littleEndian: withUnsafeBytes { $0.load(as: UInt32.self) }))
    }

    /// 从 Data 头部移除并返回指定字节数的数据
    /// 若请求字节数超过实际长度，则返回全部剩余数据
    /// - Parameter k: 要移除并返回的字节数
    /// - Returns: 移除的前 k 个字节组成的 Data
    mutating func removeAndReturnFirst(_ k: Int) -> Data {
        let end = Swift.min(k, count)  // 防止越界，取实际可用字节数
        let slice = self[0..<end]
        removeFirst(end)
        return Data(slice)
    }
}

// MARK: - 整数数据转换扩展

/// 固定宽度整数的数据转换扩展
public extension FixedWidthInteger {

    /// 将整数的原始字节表示转换为 Data（平台字节序）
    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }

    /// 将整数转换为 BCD（Binary-Coded Decimal）编码的 UInt8 数组
    /// 每个字节存储两位十进制数字（高四位为十位，低四位为个位）
    var bcdValue: [UInt8] {
        let str = Array("\(self)")
        // 计算需要的字节数（每两位十进制数字占一个字节，奇数位向上取整）
        let snippetCount = (str.count / 2) + (str.count % 2 == 0 ? 0 : 1)
        let arr = (1...snippetCount).reversed().map({ index -> UInt8 in
            let endIndex = Swift.min(index * 2 - 1, str.count - 1)
            let startIndex = Swift.max(endIndex - 1, 0)
            let string = String(str[startIndex...endIndex])
            let int = Int(string)!
            // 高四位存十位数字，低四位存个位数字
            let uint8: UInt8 = UInt8(int / 10 * 16 + int % 10)
            return uint8
        })
        return arr.reversed()
    }

    /// 将整数截断为 UInt8（取模 256，保留最低字节）
    var uint8: UInt8 {
        UInt8(self % 256)
    }
}

// MARK: - Float 扩展

/// Float 的字节操作扩展
public extension Float {

    /// 将 Float 转换为小端序 UInt8 字节数组（IEEE 754 单精度）
    var bytes: [UInt8] {
        withUnsafeBytes(of: self, Array.init)
    }

    /// 将 Float 转换为 Data（小端序字节表示）
    func dataValue() -> Data {
        return Data(bytes)
    }
}

// MARK: - UInt8 扩展

/// UInt8 的 BCD 解码扩展
public extension UInt8 {
    /// 将 BCD 编码的 UInt8 解码为十进制 Int
    /// 高四位为十位数字，低四位为个位数字
    /// 例：0x42 -> 42
    var bcdValue: Int {
        Int(self / 16 * 10 + self % 16)
    }
}

// MARK: - [UInt8] 扩展

/// UInt8 数组的十六进制字符串及十进制值扩展
public extension Array where Element == UInt8 {

    /// 将字节数组转换为大写十六进制字符串（无分隔符）
    /// 例：[0x0A, 0xFF] -> "0AFF"
    var hexString: String {
        return self.compactMap { String(format: "%02x", $0).uppercased() }.joined(separator: "")
    }

    /// 将字节数组按十六进制位权累加转换为十进制 Int
    /// 索引 0 对应最低位（16^0），索引 n 对应 16^n
    var decimalValue: Int {
        enumerated().reduce(0, { $0 + Int($1.element) * Int(pow(16, Double($1.offset))) })
    }
}

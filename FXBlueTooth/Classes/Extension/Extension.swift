//
//  Extension.swift
//  BleManager
//
//  Created by mac on 2021/5/10.
//

import Foundation

// MARK: - Convenience Extension Methods
extension FixedWidthInteger {
    public var bigEndianBytes: [UInt8] {
        [UInt8](withUnsafeBytes(of: self.bigEndian) { Data($0) })
    }
}

// `BinaryFloatingPoint` conforms to 754-2008 - IEEE Standard for Floating-Point Arithmetic (https://ieeexplore.ieee.org/document/4610935)
// If you target system is using a different floating point representation, you need to adapt accordingly
extension BinaryFloatingPoint {
    public var bigEndianBytes: [UInt8] {
        [UInt8](withUnsafeBytes(of: self) { Data($0) }).reversed()
    }
}

public extension Data {
    var array: Array<Element> {
        return Array(self)
    }
    
    /*
     转换成十进制，低高字节
     let bytes = Data([0x01, 0x02])

     bytes.toInt() // 513
     */
    func toInt() -> Int {
        var num: Int = 0
        let data = NSData(data: self)
        data.getBytes(&num, length: MemoryLayout<Int>.size)
        return num
    }
    
    /*
      pair-wise (UInt8, UInt8) -> (bytePattern bytePattern) -> UInt16
     for byteArr:s of non-even number of elements, return nil (no padding)
     example usage:
     
     var byteArr:[UInt8] = [
         255, 255,  // 0b 1111 1111 1111 1111 = 65535
         0, 255,    // 0b 0000 0000 1111 1111 = 255
         255, 0,    // 0b 1111 1111 0000 0000 = 65535 - 255 = 65280
         104, 76]   // 0b 0110 1000 0100 1100 = 26700

     if let u16arr = Data(byteArr).byteArrToUInt16() {
         print(u16arr) // [65535, 255, 65280, 26700], OK
     }
     
     */
    func byteArrToUInt16() -> [UInt16]? {
        let byteArr = array
        let numBytes = byteArr.count
        var byteArrSlice = byteArr[0..<numBytes]

        guard numBytes % 2 == 0 else { return nil }

        var arr: [UInt16] = Array(repeating: 0, count: numBytes/2)
        
        for i in (0..<numBytes/2).reversed() {
            arr[i] = UInt16(byteArrSlice.removeLast()) +
                     UInt16(byteArrSlice.removeLast()) << 8
        }
        return arr
    }
    
    /*
     pair-wise (UInt8, UInt8, UInt8, UInt8) -> (bytePattern bytePattern) -> UInt32
     for byteArr:s of non-even number of elements, return nil (no padding)
     */
    func byteArrToUInt32() -> [UInt32]? {
        let byteArr = array
        let numBytes = byteArr.count
        var byteArrSlice = byteArr[0..<numBytes]

        guard numBytes % 4 == 0 else { return nil }

        var arr: [UInt32] = Array(repeating: 0, count: numBytes/4)
        
        for i in (0..<numBytes/4).reversed() {
            arr[i] = UInt32(byteArrSlice.removeLast()) +
                UInt32(byteArrSlice.removeLast()) << 8 +
                UInt32(byteArrSlice.removeLast()) << 16 +
                UInt32(byteArrSlice.removeLast()) << 24
        }
        return arr
    }
    
    func floatValue() -> Float {
        return Float(bitPattern: UInt32(littleEndian: withUnsafeBytes { $0.load(as: UInt32.self) }))
    }
    
}

public extension FixedWidthInteger {
    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
    
    var bcdValue: [UInt8] {
        let str = Array("\(self)")
        let snippetCount = (str.count / 2) + (str.count % 2 == 0 ? 0 : 1)
        let arr = (1...snippetCount).reversed().map({ index -> UInt8 in
            let endIndex = Swift.min(index * 2 - 1, str.count - 1)
            let startIndex = Swift.max(endIndex - 1, 0)
            let string = String(str[startIndex...endIndex])
            let int = Int(string)!
            let uint8: UInt8 = UInt8(int / 10 * 16 + int % 10)
            return uint8
        })
        
        return arr.reversed()
    }
    
    var uint8: UInt8 {
        UInt8(self % 256)
    }
}

public extension Float {
   var bytes: [UInt8] {
       withUnsafeBytes(of: self, Array.init)
   }
    
    func dataValue() -> Data {
        return Data(bytes)
    }
}

public extension UInt8 {
    var bcdValue: Int {
        Int(self / 16 * 10 + self % 16)
    }
}

public extension Array where Element == UInt8 {
    var hexString: String {
        return self.compactMap { String(format: "%02x", $0).uppercased() }.joined(separator: "")
    }
    
    var decimalValue: Int {
        enumerated().reduce(0, { $0 + Int($1.element) * Int(pow(16, Double($1.offset))) })
    }
}

public extension Data {
    mutating func removeAndReturnFirst(_ k: Int) -> Data {
        let end = Swift.min(k, count)
        let slice = self[0..<end]
        removeFirst(end)
        return Data(slice)
    }
}

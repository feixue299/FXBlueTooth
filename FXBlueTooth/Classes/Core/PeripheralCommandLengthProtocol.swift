//
//  PeripheralCommandLengthProtocol.swift
//  FXBlueTooth
//
//  Created by hard on 2021/12/30.
//

import Foundation

public protocol PeripheralCommandLengthProtocol {
    func currentLength() -> Int
}

public class DefaultPeripheralCommandLength: PeripheralCommandLengthProtocol {
    
    public let length: Int
    
    public init(length: Int = 20) {
        self.length = length
    }
    
    public func currentLength() -> Int {
        return length
    }
}

public class FirstPeripheralCommandLength: PeripheralCommandLengthProtocol {
    
    public let first: Int
    public let then: Int
    
    private var firstValue = true
    
    public init(first: Int, then: Int) {
        self.first = first
        self.then = then
    }
    
    public func currentLength() -> Int {
        if firstValue {
            firstValue = false
            return first
        } else {
            return then
        }
    }
}

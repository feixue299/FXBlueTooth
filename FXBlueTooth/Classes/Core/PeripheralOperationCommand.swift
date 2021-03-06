//
//  PeripheralOperationCommand.swift
//  FXBlueTooth
//
//  Created by hard on 2021/12/30.
//

import Foundation

public protocol PeripheralOperationCommand {
    var cmdData: Data { get }
    func checkResponse(_ dataGroup: [Data], data: Data) -> CheckResponseResult
    func filterData(_ data: Data) -> Data?
    func getLengthProtocol() -> PeripheralCommandLengthProtocol
    var timeOutInterval: TimeInterval { get }
}

public extension PeripheralOperationCommand {
    func getLengthProtocol() -> PeripheralCommandLengthProtocol {
        return DefaultPeripheralCommandLength()
    }
    var timeOutInterval: TimeInterval {
        return 20
    }
}

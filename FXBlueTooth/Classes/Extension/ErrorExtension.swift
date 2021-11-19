//
//  ErrorExtension.swift
//  BleManager
//
//  Created by mac on 2021/5/24.
//

import Foundation

public extension NSError {
    static func error(description: String) -> NSError {
        return NSError(domain: "BleManager Module", code: -1, userInfo: [NSLocalizedDescriptionKey : description])
    }
}

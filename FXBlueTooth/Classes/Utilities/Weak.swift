//
//  Weak.swift
//  HTBleManager
//
//  Created by mac on 2021/7/17.
//

import Foundation

class Weak<T: AnyObject>: NSObject {
  weak var value : T?
  init (value: T) {
    self.value = value
  }
}

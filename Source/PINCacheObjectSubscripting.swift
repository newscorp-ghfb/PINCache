//  Converted to Swift 5.1 by Swiftify v5.1.27756 - https://objectivec2swift.com/
//
//  PINCacheObjectSubscripting.swift
//  PINCache
//
//  Created by Rocir Marcos Leite Santiago on 4/2/16.
//  Copyright © 2016 Pinterest. All rights reserved.
//

import Foundation

@objc
public
protocol PINCacheObjectSubscripting {
    /**
     This method enables using literals on the receiving object, such as `id object = cache[@"key"];`.

     @param key The key associated with the object.
     @result The object for the specified key.
     */
    subscript(key: String) -> Cacheable? { get set }
}

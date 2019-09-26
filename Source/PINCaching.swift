//  Converted to Swift 5.1 by Swiftify v5.1.27756 - https://objectivec2swift.com/
//
//  PINCaching.swift
//  PINCache
//
//  Created by Michael Schneider on 1/31/17.
//  Copyright © 2017 Pinterest. All rights reserved.
//

import Foundation

@objc
public protocol Cacheable {
    func serialize() throws
    func deserialize() throws
}

public
extension Cacheable where Self: Codable {
    func serialze() throws {
        withUnsafePointer(to: self) { (p) -> Data in
            return Data(buffer: p.)
        }
        Data(self)
        let container = SingleValueEncodingContainer.
        let encoder = Data(self.)
        self.encode(to: <#T##Encoder#>)
    }
    
    func deserialize() throws {
        
    }
}

public
extension Cacheable where Self: NSCoding {
    func serialze() {
        
    }
    
    func deserialize() {
        
    }
}

/**
 A callback block which provides only the cache as an argument
 */
public typealias PINCacheBlock = (PINCaching) -> Void

public typealias PINCacheClosure<P:PINCaching> = (P) -> Void

/**
 A callback block which provides the cache, key and object as arguments
 */
public typealias PINCacheObjectBlock = (PINCaching, String, Any?) -> Void

public typealias PINCacheObjectClosure<P:PINCaching> = (P, String, Any?) -> Void

/**
 A callback block used for enumeration which provides the cache, key and object as arguments plus a stop flag that
 may be flipped by the caller.
 */
public typealias PINCacheObjectEnumerationBlock = (PINCaching, String, Any?, inout Bool ) -> Void

public typealias PINCacheObjectEnumerationClosure<P:PINCaching> = (P, String, Any?, inout Bool ) -> Void

/**
 A callback block which provides a BOOL value as argument
 */
public typealias PINCacheObjectContainmentBlock = (Bool) -> Void

@objc
public protocol PINCaching: NSObjectProtocol {
    // MARK: - Core

    /**
     The name of this cache, used to create a directory under Library/Caches and also appearing in stack traces.
     */
    var name: String { get }
    
    // MARK: - Asynchronous Methods

    /// @name Asynchronous Methods

    /**
     This method determines whether an object is present for the given key in the cache. This method returns immediately
     and executes the passed block after the object is available, potentially in parallel with other blocks on the
     <concurrentQueue>.

     @see containsObjectForKey:
     @param key The key associated with the object.
     @param block A block to be executed concurrently after the containment check happened
     */
    func containsObject(forKeyAsync key: String, completion block: PINCacheObjectContainmentBlock)
    /**
     Retrieves the object for the specified key. This method returns immediately and executes the passed
     block after the object is available, potentially in parallel with other blocks on the <concurrentQueue>.

     @param key The key associated with the requested object.
     @param block A block to be executed concurrently when the object is available.
     */
    func object(forKeyAsync key: String, completion block: PINCacheObjectBlock)
    /**
     Stores an object in the cache for the specified key. This method returns immediately and executes the
     passed block after the object has been stored, potentially in parallel with other blocks on the <concurrentQueue>.

     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param block A block to be executed concurrently after the object has been stored, or nil.
     */
    func setObjectAsync(_ object: Any, forKey key: String, completion block: PINCacheObjectBlock?)
    /**
     Stores an object in the cache for the specified key and the specified age limit. This method returns immediately
     and executes the passed block after the object has been stored, potentially in parallel with other blocks
     on the <concurrentQueue>.

     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param ageLimit The age limit (in seconds) to associate with the object. An age limit <= 0 means there is no object-level age limit and the
                     cache-level TTL will be used for this object.
     @param block A block to be executed concurrently after the object has been stored, or nil.
     */
    @objc(setObjectAsync:forKey:withAgeLimit:completion:)
    func setObjectAsync(_ object: Any, forKey key: String, ageLimit: TimeInterval, completion block: PINCacheObjectBlock?)
    /**
     Stores an object in the cache for the specified key and the specified memory cost. If the cost causes the total
     to go over the <memoryCache.costLimit> the cache is trimmed (oldest objects first). This method returns immediately
     and executes the passed block after the object has been stored, potentially in parallel with other blocks
     on the <concurrentQueue>.

     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param cost An amount to add to the <memoryCache.totalCost>.
     @param block A block to be executed concurrently after the object has been stored, or nil.
     */
    @objc(setObjectAsync:forKey:withCost:completion:)
    func setObjectAsync(_ object: Any, forKey key: String, cost: UInt, completion block: PINCacheObjectBlock?)
    /**
     Stores an object in the cache for the specified key and the specified memory cost and age limit. If the cost causes the total
     to go over the <memoryCache.costLimit> the cache is trimmed (oldest objects first). This method returns immediately
     and executes the passed block after the object has been stored, potentially in parallel with other blocks
     on the <concurrentQueue>.

     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param cost An amount to add to the <memoryCache.totalCost>.
     @param ageLimit The age limit (in seconds) to associate with the object. An age limit <= 0 means there is no object-level age limit and the cache-level TTL will be
                     used for this object.
     @param block A block to be executed concurrently after the object has been stored, or nil.
     */
    @objc(setObjectAsync:forKey:withCost:ageLimit:completion:)
    func setObjectAsync(_ object: Any, forKey key: String, cost: UInt, ageLimit: TimeInterval, completion block: PINCacheObjectBlock?)
    /**
     Removes the object for the specified key. This method returns immediately and executes the passed
     block after the object has been removed, potentially in parallel with other blocks on the <concurrentQueue>.

     @param key The key associated with the object to be removed.
     @param block A block to be executed concurrently after the object has been removed, or nil.
     */
    func removeObject(forKeyAsync key: String, completion block: PINCacheObjectBlock?)
    /**
     Removes all objects from the cache that have not been used since the specified date. This method returns immediately and
     executes the passed block after the cache has been trimmed, potentially in parallel with other blocks on the <concurrentQueue>.

     @param date Objects that haven't been accessed since this date are removed from the cache.
     @param block A block to be executed concurrently after the cache has been trimmed, or nil.
     */
    func trim(toDateAsync date: Date, completion block: PINCacheBlock?)
    /**
     Removes all expired objects from the cache. This includes objects that are considered expired due to the cache-level ageLimit
     as well as object-level ageLimits. This method returns immediately and executes the passed block after the objects have been removed,
     potentially in parallel with other blocks on the <concurrentQueue>.

     @param block A block to be executed concurrently after the objects have been removed, or nil.
     */
    func removeExpiredObjectsAsync(_ block: PINCacheBlock?)
    /**
     Removes all objects from the cache.This method returns immediately and executes the passed block after the
     cache has been cleared, potentially in parallel with other blocks on the <concurrentQueue>.

     @param block A block to be executed concurrently after the cache has been cleared, or nil.
     */
    func removeAllObjectsAsync(_ block: PINCacheBlock?)
    
    // MARK: - Synchronous Methods
    /// @name Synchronous Methods

    /**
     This method determines whether an object is present for the given key in the cache.

     @see containsObjectForKeyAsync:completion:
     @param key The key associated with the object.
     @result YES if an object is present for the given key in the cache, otherwise NO.
     */
    func containsObject(forKey key: String) -> Bool
    /**
     Retrieves the object for the specified key. This method blocks the calling thread until the object is available.
     Uses a lock to achieve synchronicity on the disk cache.

     @see objectForKeyAsync:completion:
     @param key The key associated with the object.
     @result The object for the specified key.
     */
    func object(forKey key: String) -> Any?
    /**
     Stores an object in the cache for the specified key. This method blocks the calling thread until the object has been set.
     Uses a lock to achieve synchronicity on the disk cache.

     @see setObjectAsync:forKey:completion:
     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     */
    func setObject(_ object: Any, forKey key: String)
    /**
     Stores an object in the cache for the specified key and age limit. This method blocks the calling thread until the
     object has been set. Uses a lock to achieve synchronicity on the disk cache.

     @see setObjectAsync:forKey:completion:
     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param ageLimit The age limit (in seconds) to associate with the object. An age limit <= 0 means there is no
                     object-level age limit and the cache-level TTL will be used for this object.
     */
    func setObject(_ object: Any, forKey key: String, withAgeLimit ageLimit: TimeInterval)
    /**
     Stores an object in the cache for the specified key and the specified memory cost. If the cost causes the total
     to go over the <memoryCache.costLimit> the cache is trimmed (oldest objects first). This method blocks the calling thread
     until the object has been stored.

     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param cost An amount to add to the <memoryCache.totalCost>.
     */
    func setObject(_ object: Any, forKey key: String, withCost cost: UInt)
    /**
     Stores an object in the cache for the specified key and the specified memory cost and age limit. If the cost causes the total
     to go over the <memoryCache.costLimit> the cache is trimmed (oldest objects first). This method blocks the calling thread
     until the object has been stored.

     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param cost An amount to add to the <memoryCache.totalCost>.
     @param ageLimit The age limit (in seconds) to associate with the object. An age limit <= 0 means there is no object-level age
                     limit and the cache-level TTL will be used for this object.
     */
    func setObject(_ object: Any, forKey key: String, withCost cost: UInt, ageLimit: TimeInterval)
    /**
     Removes the object for the specified key. This method blocks the calling thread until the object
     has been removed.
     Uses a lock to achieve synchronicity on the disk cache.

     @see removeObjectForKeyAsync:completion:
     @param key The key associated with the object to be removed.
     */
    func removeObject(forKey key: String)
    /**
     Removes all objects from the cache that have not been used since the specified date.
     This method blocks the calling thread until the cache has been trimmed.
     Uses a lock to achieve synchronicity on the disk cache.

     @see trimToDateAsync:completion:
     @param date Objects that haven't been accessed since this date are removed from the cache.
     */
    func trim(to date: Date)
    /**
     Removes all expired objects from the cache. This includes objects that are considered expired due to the cache-level ageLimit
     as well as object-level ageLimits. This method blocks the calling thread until the objects have been removed.
     Uses a lock to achieve synchronicity on the disk cache.
     */
    func removeExpiredObjects()
    /**
     Removes all objects from the cache. This method blocks the calling thread until the cache has been cleared.
     Uses a lock to achieve synchronicity on the disk cache.

     @see removeAllObjectsAsync:
     */
    func removeAllObjects()
}

//public extension PINCaching {
//    func setObjectAsync(_ object: Any, forKey key: String, completion block: PINCacheObjectBlock?) {
//        setObjectAsync(object, forKey: key, withCost: 0, ageLimit: 0, completion: block)
//    }
//    
//    func setObjectAsync(_ object: Any, forKey key: String, withAgeLimit ageLimit: TimeInterval, completion block: PINCacheObjectBlock?) {
//        setObjectAsync(object, forKey: key, withCost: 0, ageLimit: ageLimit, completion: block)
//    }
//    
//    func setObjectAsync(_ object: Any, forKey key: String, withCost cost: UInt, completion block: PINCacheObjectBlock?) {
//        setObjectAsync(object, forKey: key, withCost: cost, ageLimit: 0, completion: block)
//    }
//    
//    func setObject(_ object: Any, forKey key: String) {
//        setObjectAsync(object, forKey: key, withCost: 0, ageLimit: 0, completion: nil)
//    }
//    
//    func setObject(_ object: Any, forKey key: String, withAgeLimit ageLimit: TimeInterval) {
//        setObjectAsync(object, forKey: key, withCost: 0, ageLimit: ageLimit, completion: nil)
//    }
//    
//    func setObject(_ object: Any, forKey key: String, withCost cost: UInt) {
//        setObjectAsync(object, forKey: key, withCost: cost, ageLimit: 0, completion: nil)
//    }
//}

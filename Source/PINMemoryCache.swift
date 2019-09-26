//  Converted to Swift 5.1 by Swiftify v5.1.27756 - https://objectivec2swift.com/
//  PINCache is a modified version of TMCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

import Foundation
import PINOperation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Deprecated
typealias PINMemoryCacheBlock = (PINMemoryCache) -> Void
typealias PINMemoryCacheObjectBlock = (PINMemoryCache, String, Any?) -> Void
typealias PINMemoryCacheContainmentBlock = (Bool) -> Void

private let PINMemoryCachePrefix = "com.pinterest.PINMemoryCache"
private let PINMemoryCacheSharedName = "PINMemoryCacheSharedName"

/**
 `PINMemoryCache` is a fast, thread safe key/value store similar to `NSCache`. On iOS it will clear itself
 automatically to reduce memory usage when the app receives a memory warning or goes into the background.

 Access is natively synchronous. Asynchronous variations are provided. Every asynchronous method accepts a
 callback block that runs on a concurrent <concurrentQueue>, with cache reads and writes protected by a lock.

 All access to the cache is dated so the that the least-used objects can be trimmed first. Setting an
 optional <ageLimit> will trigger a GCD timer to periodically to trim the cache to that age.

 Objects can optionally be set with a "cost", which could be a byte count or any other meaningful integer.
 Setting a <costLimit> will automatically keep the cache below that value with <trimToCostByDate:>.

 Values will not persist after application relaunch or returning from the background. See <PINCache> for
 a memory cache backed by a disk cache.
 */
class PINMemoryCache: NSObject, PINCaching, PINCacheObjectSubscripting {
// MARK: - Properties
    /// @name Core

    /**
     The total accumulated cost.
     */

    private var _totalCost: UInt = 0
    var totalcost: UInt {
        lock()
        let cost = _totalCost
        unlock()

        return cost
    }
    /**
     The maximum cost allowed to accumulate before objects begin to be removed with <trimToCostByDate:>.
     */

    private var _costLimit: UInt = 0
    var costLimit: UInt {
        get {
            lock()
            let costLimit = _costLimit
            unlock()

            return costLimit
        }
        set(costLimit) {
            lock()
            _costLimit = costLimit
            unlock()

            if costLimit > 0 {
                trimToCostLimit(byDate: costLimit)
            }
        }
    }
    /**
     The maximum number of seconds an object is allowed to exist in the cache. Setting this to a value
     greater than `0.0` will start a recurring GCD timer with the same period that calls <trimToDate:>.
     Setting it back to `0.0` will stop the timer. Defaults to `0.0`.
     */

    private var _ageLimit: TimeInterval = 0.0
    var ageLimit: TimeInterval {
        get {
            lock()
            let ageLimit = _ageLimit
            unlock()

            return ageLimit
        }
        set(ageLimit) {
            lock()
            _ageLimit = ageLimit
            unlock()

            trimToAgeLimitRecursively()
        }
    }
    /**
     If ttlCache is YES, the cache behaves like a ttlCache. This means that once an object enters the
     cache, it only lives as long as self.ageLimit. This has the following implications:
     - Accessing an object in the cache does not extend that object's lifetime in the cache
     - When attempting to access an object in the cache that has lived longer than self.ageLimit,
     the cache will behave as if the object does not exist

     @note If an object-level age limit is set via one of the @c -setObject:forKey:withAgeLimit methods,
           that age limit overrides self.ageLimit. The overridden object age limit could be greater or
           less than self.agelimit but must be greater than zero.
     */

    private var _ttlCache = false
    var ttlCache: Bool {
        var isTTLCache: Bool

        lock()
        isTTLCache = _ttlCache
        unlock()

        return isTTLCache
    }
    /**
     When `YES` on iOS the cache will remove all objects when the app receives a memory warning.
     Defaults to `YES`.
     */
    var removeAllObjectsOnMemoryWarning = false
    /**
     When `YES` on iOS the cache will remove all objects when the app enters the background.
     Defaults to `YES`.
     */
    var removeAllObjectsOnEnteringBackground = false
// MARK: - Event Blocks
    /// @name Event Blocks

    /**
     A block to be executed just before an object is added to the cache. This block will be excuted within
     a lock, i.e. all reads and writes are suspended for the duration of the block.
     Calling synchronous methods on the cache within this callback will likely cause a deadlock.
     */

    private var _willAddObjectBlock: PINCacheObjectBlock?
    var willAddObjectBlock: PINCacheObjectBlock? {
        get {
            lock()
            let block = _willAddObjectBlock as? PINCacheObjectBlock
            unlock()

            return block!
        }
        set(block) {
            lock()
            _willAddObjectBlock = block.copy()
            unlock()
        }
    }
    /**
     A block to be executed just before an object is removed from the cache. This block will be excuted
     within a lock, i.e. all reads and writes are suspended for the duration of the block.
     Calling synchronous methods on the cache within this callback will likely cause a deadlock.
     */

    private var _willRemoveObjectBlock: PINCacheObjectBlock?
    var willRemoveObjectBlock: PINCacheObjectBlock? {
        get {
            lock()
            let block = _willRemoveObjectBlock as? PINCacheObjectBlock
            unlock()

            return block!
        }
        set(block) {
            lock()
            _willRemoveObjectBlock = block.copy()
            unlock()
        }
    }
    /**
     A block to be executed just before all objects are removed from the cache as a result of <removeAllObjects:>.
     This block will be excuted within a lock, i.e. all reads and writes are suspended for the duration of the block.
     Calling synchronous methods on the cache within this callback will likely cause a deadlock.
     */

    private var _willRemoveAllObjectsBlock: PINCacheBlock?
    var willRemoveAllObjectsBlock: PINCacheBlock? {
        get {
            lock()
            let block = _willRemoveAllObjectsBlock
            unlock()

            return block!
        }
        set(block) {
            lock()
            _willRemoveAllObjectsBlock = block
            unlock()
        }
    }
    /**
     A block to be executed just after an object is added to the cache. This block will be excuted within
     a lock, i.e. all reads and writes are suspended for the duration of the block.
     Calling synchronous methods on the cache within this callback will likely cause a deadlock.
     */

    private var _didAddObjectBlock: PINCacheObjectBlock?
    var didAddObjectBlock: PINCacheObjectBlock? {
        get {
            lock()
            let block = _didAddObjectBlock as? PINCacheObjectBlock
            unlock()

            return block!
        }
        set(block) {
            lock()
            _didAddObjectBlock = block
            unlock()
        }
    }
    /**
     A block to be executed just after an object is removed from the cache. This block will be excuted
     within a lock, i.e. all reads and writes are suspended for the duration of the block.
     Calling synchronous methods on the cache within this callback will likely cause a deadlock.
     */

    private var _didRemoveObjectBlock: PINCacheObjectBlock?
    var didRemoveObjectBlock: PINCacheObjectBlock? {
        get {
            lock()
            let block = _didRemoveObjectBlock as? PINCacheObjectBlock
            unlock()

            return block!
        }
        set(block) {
            lock()
            _didRemoveObjectBlock = block
            unlock()
        }
    }
    /**
     A block to be executed just after all objects are removed from the cache as a result of <removeAllObjects:>.
     This block will be excuted within a lock, i.e. all reads and writes are suspended for the duration of the block.
     Calling synchronous methods on the cache within this callback will likely cause a deadlock.
     */

    private var _didRemoveAllObjectsBlock: PINCacheBlock?
    var didRemoveAllObjectsBlock: PINCacheBlock? {
        get {
            lock()
            let block = _didRemoveAllObjectsBlock
            unlock()

            return block!
        }
        set(block) {
            lock()
            _didRemoveAllObjectsBlock = block
            unlock()
        }
    }
    /**
     A block to be executed upon receiving a memory warning (iOS only) potentially in parallel with other blocks on the <queue>.
     This block will be executed regardless of the value of <removeAllObjectsOnMemoryWarning>. Defaults to `nil`.
     */

    private var _didReceiveMemoryWarningBlock: PINCacheBlock?
    var didReceiveMemoryWarningBlock: PINCacheBlock? {
        get {
            lock()
            let block = _didReceiveMemoryWarningBlock
            unlock()

            return block!
        }
        set(block) {
            lock()
            _didReceiveMemoryWarningBlock = block
            unlock()
        }
    }
    /**
     A block to be executed when the app enters the background (iOS only) potentially in parallel with other blocks on the <concurrentQueue>.
     This block will be executed regardless of the value of <removeAllObjectsOnEnteringBackground>. Defaults to `nil`.
     */

    private var _didEnterBackgroundBlock: PINCacheBlock?
    var didEnterBackgroundBlock: PINCacheBlock? {
        get {
            lock()
            let block = _didEnterBackgroundBlock
            unlock()

            return block!
        }
        set(block) {
            lock()
            _didEnterBackgroundBlock = block
            unlock()
        }
    }
// MARK: - Lifecycle
    /// @name Shared Cache

    /**
     A shared cache.

     @result The shared singleton cache instance.
     */
    private(set) var sharedCache: PINMemoryCache?

    convenience init(operationQueue: PINOperationQueue) {
        self.init(name: PINMemoryCacheSharedName, operationQueue: operationQueue)
    }

    convenience init(name: String, operationQueue: PINOperationQueue) {
        self.init(name: name, operationQueue: operationQueue, ttlCache: false)
    }

    required init(name: String, operationQueue: PINOperationQueue, ttlCache: Bool) {
        super.init() != nil
            self.name = name
            self.operationQueue = operationQueue
            self.ttlCache = ttlCache

            dictionary = [:]
            createdDates = [:]
            accessDates = [:]
            costs = [:]
            ageLimits = [:]

            willAddObjectBlock = nil
            willRemoveObjectBlock = nil
            willRemoveAllObjectsBlock = nil

            didAddObjectBlock = nil
            didRemoveObjectBlock = nil
            didRemoveAllObjectsBlock = nil

            didReceiveMemoryWarningBlock = nil
            didEnterBackgroundBlock = nil

            ageLimit = 0.0
            costLimit = 0
            totalCost = 0

            removeAllObjectsOnMemoryWarning = true
            removeAllObjectsOnEnteringBackground = true

        #if os(iOS) || os(tvOS)
            NotificationCenter.default.addObserver(self, selector: #selector(didReceiveEnterBackgroundNotification(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(didReceiveMemoryWarning(_:)), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        #endif
    }

// MARK: - Asynchronous Methods
    /// @name Asynchronous Methods

    /**
     Removes objects from the cache, costliest objects first, until the <totalCost> is below the specified
     value. This method returns immediately and executes the passed block after the cache has been trimmed,
     potentially in parallel with other blocks on the <concurrentQueue>.

     @param cost The total accumulation allowed to remain after the cache has been trimmed.
     @param block A block to be executed concurrently after the cache has been trimmed, or nil.
     */
    func trim(toCostAsync cost: UInt, completion block: PINCacheBlock) {
        operationQueue.scheduleOperation({
            self.trim(toCost: cost)

            
                block(self)
        }, with: .low)
    }

    /**
     Removes objects from the cache, ordered by date (least recently used first), until the <totalCost> is below
     the specified value. This method returns immediately and executes the passed block after the cache has been
     trimmed, potentially in parallel with other blocks on the <concurrentQueue>.

     @param cost The total accumulation allowed to remain after the cache has been trimmed.
     @param block A block to be executed concurrently after the cache has been trimmed, or nil.
     */
    func trimToCost(byDateAsync cost: UInt, completion block: PINCacheBlock) {
        operationQueue.scheduleOperation({
            self.trimToCost(byDate: cost)

                block(self)
        }, with: .low)
    }

    /**
     Loops through all objects in the cache with reads and writes suspended. Calling serial methods which
     write to the cache inside block may be unsafe and may result in a deadlock. This method returns immediately.

     @param block A block to be executed for every object in the cache.
     @param completionBlock An optional block to be executed concurrently when the enumeration is complete.
     */
    func enumerateObjects(withBlockAsync block: PINCacheObjectEnumerationBlock, completionBlock: PINCacheBlock) {
        operationQueue.scheduleOperation({
            self.enumerateObjects(with: block)

            if completionBlock != nil {
                completionBlock(self)
            }
        }, with: .low)
    }

// MARK: - Synchronous Methods
    /// @name Synchronous Methods

    /**
     Removes objects from the cache, costliest objects first, until the <totalCost> is below the specified
     value. This method blocks the calling thread until the cache has been trimmed.

     @see trimToCostAsync:
     @param cost The total accumulation allowed to remain after the cache has been trimmed.
     */
    func trim(toCost cost: UInt) {
        trim(toCostLimit: cost)
    }

    /**
     Removes objects from the cache, ordered by date (least recently used first), until the <totalCost> is below
     the specified value. This method blocks the calling thread until the cache has been trimmed.

     @see trimToCostByDateAsync:
     @param cost The total accumulation allowed to remain after the cache has been trimmed.
     */
    func trimToCost(byDate cost: UInt) {
        trimToCostLimit(byDate: cost)
    }

    /**
     Loops through all objects in the cache within a memory lock (reads and writes are suspended during the enumeration).
     This method blocks the calling thread until all objects have been enumerated.
     Calling synchronous methods on the cache within this callback will likely cause a deadlock.

     @see enumerateObjectsWithBlockAsync:completionBlock:
     @param block A block to be executed for every object in the cache.

     @warning Do not call this method within the event blocks (<didReceiveMemoryWarningBlock>, etc.)
     Instead use the asynchronous version, <enumerateObjectsWithBlock:completionBlock:>.

     */
    func enumerateObjects(with block: PINCacheObjectEnumerationBlock) {
        if block == nil {
            return
        }

        lock()
        let now = Date()
        let keysSortedByCreatedDate = (createdDates as NSDictionary).keysSortedByValue(using: #selector(AnyHashable.compare(_:)))

        for key in keysSortedByCreatedDate {
            guard let key = key as? String else {
                continue
            }
            // If the cache should behave like a TTL cache, then only fetch the object if there's a valid ageLimit and  the object is still alive
            let ageLimit = (ageLimits[key] as? NSNumber)?.doubleValue ?? self.ageLimit
            if !ttlCache || ageLimit <= 0 || fabs(Float(createdDates[key]?.timeIntervalSince(now) ?? 0.0)) < Float(ageLimit) {
                var stop = false
                block(self, key, dictionary[key], &stop)
                if stop {
                    break
                }
            }
        }
        unlock()
    }

    private var name = ""
    private var operationQueue: PINOperationQueue
    private var lock = os_unfair_lock_s()
    private var dictionary: [AnyHashable : Any] = [:]
    private var createdDates: [AnyHashable : Any] = [:]
    private var accessDates: [AnyHashable : Any] = [:]
    private var costs: [AnyHashable : Any] = [:]
    private var ageLimits: [AnyHashable : Any] = [:]

// MARK: - Initialization -
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    convenience init() {
        self.init(operationQueue: PINOperationQueue.shared())
    }

    static var cache: PINMemoryCache?

    class func shared() -> PINMemoryCache {

        // `dispatch_once()` call was converted to a static variable initializer

        return cache!
    }

// MARK: - Private Methods -
    @objc func didReceiveMemoryWarning(_ notification: Notification) {
        if removeAllObjectsOnMemoryWarning {
            removeAllObjectsAsync(nil)
        }

        removeExpiredObjects()

        operationQueue.scheduleOperation({
            self.lock()
            let didReceiveMemoryWarningBlock = self.didReceiveMemoryWarningBlock
            self.unlock()

            if didReceiveMemoryWarningBlock != nil {
                didReceiveMemoryWarningBlock?(self)
            }
        }, with: .high)
    }

    @objc func didReceiveEnterBackgroundNotification(_ notification: Notification) {
        if removeAllObjectsOnEnteringBackground {
            removeAllObjectsAsync(nil)
        }

        operationQueue.scheduleOperation({
            self.lock()
            let didEnterBackgroundBlock = self.didEnterBackgroundBlock
            self.unlock()

            if didEnterBackgroundBlock != nil {
                didEnterBackgroundBlock?(self)
            }
        }, with: .high)
    }

    func removeObjectAndExecuteBlocks(forKey key: String) {
        lock()
        let object = dictionary[key]
        let cost = costs[key] as? NSNumber
        let willRemoveObjectBlock = self.willRemoveObjectBlock
        let didRemoveObjectBlock = self.didRemoveObjectBlock
        unlock()

        willRemoveObjectBlock?(self, key, object)

        lock()
        if cost != nil {
            totalCost -= Int(cost?.uintValue ?? 0)
        }

        dictionary.removeValue(forKey: key)
        createdDates.removeValue(forKey: key)
        accessDates.removeValue(forKey: key)
        costs.removeValue(forKey: key)
        ageLimits.removeValue(forKey: key)
        unlock()

        if didRemoveObjectBlock != nil {
            didRemoveObjectBlock?(self, key, nil)
        }
    }

    func trimMemory(to trimDate: Date) {
        lock()
        let keysSortedByCreatedDate = self.createdDates.keysSortedByValue(using: #selector(compare(_:)))
        let createdDates = self.createdDates.copy()
        let ageLimits = self.ageLimits.copy()
        unlock()

        for key in keysSortedByCreatedDate {
            guard let key = key as? String else {
                continue
            }
            // oldest objects first
            let createdDate = createdDates[key] as? Date
            let ageLimit = TimeInterval((ageLimits[key] as? NSNumber)?.doubleValue)
            if createdDate == nil || ageLimit > 0.0 {
                continue
            }

            if createdDate?.compare(trimDate) == .orderedAscending {
                // older than trim date
                removeObjectAndExecuteBlocks(forKey: key)
            } else {
                break
            }
        }
    }

    func removeExpiredObjects() {
        lock()
        let createdDates = self.createdDates.copy()
        let ageLimits = self.ageLimits.copy()
        let globalAgeLimit = self.ageLimit
        unlock()

        let now = Date()
        for key in ageLimits {
            guard let key = key as? String else {
                continue
            }
            let createdDate = createdDates[key]
            let ageLimit = ageLimits[key].doubleValue ?? globalAgeLimit
            if createdDate == nil {
                continue
            }

            let expirationDate = createdDate.addingTimeInterval(ageLimit) as? Date
            if expirationDate?.compare(now) == .orderedAscending {
                // Expiration date has passed
                removeObjectAndExecuteBlocks(forKey: key)
            }
        }
    }

    func trim(toCostLimit limit: Int) {
        var totalCost = 0

        lock()
        totalCost = self.totalCost
        let keysSortedByCost = (costs as NSDictionary).keysSortedByValue(using: #selector(AnyHashable.compare(_:)))
        unlock()

        if totalCost <= limit {
            return
        }

        for key in (keysSortedByCost as NSArray).reverseObjectEnumerator() {
            guard let key = key as? String else {
                continue
            }
            // costliest objects first
            removeObjectAndExecuteBlocks(forKey: key)

            lock()
            totalCost = self.totalCost
            unlock()

            if totalCost <= limit {
                break
            }
        }
    }

    func trimToCostLimit(byDate limit: UInt) {
        if isTTLCache {
            removeExpiredObjects()
        }

        var totalCost = 0

        lock()
        totalCost = self.totalCost
        let keysSortedByAccessDate = (accessDates as NSDictionary).keysSortedByValue(using: #selector(AnyHashable.compare(_:)))
        unlock()

        if totalCost <= limit {
            return
        }

        for key in keysSortedByAccessDate {
            guard let key = key as? String else {
                continue
            }
            // oldest objects first
            removeObjectAndExecuteBlocks(forKey: key)

            lock()
            totalCost = self.totalCost
            unlock()
            if totalCost <= limit {
                break
            }
        }
    }

    func trimToAgeLimitRecursively() {
        lock()
        let ageLimit = self.ageLimit
        unlock()

        if ageLimit == 0.0 {
            return
        }

        let date = Date(timeIntervalSinceNow: -ageLimit)

        trimMemory(to: date)

        let time = DispatchTime.now() + Double(Int64(ageLimit * Double(NSEC_PER_SEC)))
        DispatchQueue.global(qos: .default).asyncAfter(deadline: time / Double(NSEC_PER_SEC), execute: {
            // Ensure that ageLimit is the same as when we were scheduled, otherwise, we've been
            // rescheduled (another dispatch_after was issued) and should cancel.
            var shouldReschedule = true
            self.lock()
            if ageLimit != self.ageLimit {
                shouldReschedule = false
            }
            self.unlock()

            if shouldReschedule {
                self.operationQueue.scheduleOperation({
                    self.trimToAgeLimitRecursively()
                }, with: .low)
            }
        })
    }

// MARK: - Public Asynchronous Methods -
    func containsObject(forKeyAsync key: String, completion block: PINCacheObjectContainmentBlock) {
        if key == "" || block == nil {
            return
        }

        operationQueue.scheduleOperation({
            let containsObject = self.containsObject(forKey: key)

            block(containsObject)
        }, with: .high)
    }

    func object(forKeyAsync key: String, completion block: PINCacheObjectBlock) {
//        guard let block = block else {
//            return
//        }

        operationQueue.scheduleOperation({
            let object = self[key]

            block(self, key, object)
        }, with: .high)
    }

    func setObjectAsync(_ object: Any?, forKey key: String, completion block: PINCacheObjectBlock) {
        setObjectAsync(object, forKey: key, withCost: 0, completion: block)
    }

    func setObjectAsync(_ object: Any?, forKey key: String, withAgeLimit ageLimit: TimeInterval, completion block: PINCacheObjectBlock) {
        setObjectAsync(object, forKey: key, withCost: 0, ageLimit: ageLimit, completion: block)
    }

    func setObjectAsync(_ object: Any?, forKey key: String, withCost cost: UInt, completion block: PINCacheObjectBlock) {
        setObjectAsync(object, forKey: key, withCost: cost, ageLimit: 0.0, completion: block)
    }

    func setObjectAsync(_ object: Any?, forKey key: String, withCost cost: UInt, ageLimit: TimeInterval, completion block: PINCacheObjectBlock) {
        operationQueue.scheduleOperation({
            self.setObject(object, forKey: key, withCost: cost, ageLimit: ageLimit)

                block(self, key, object)
        }, with: .high)
    }

    func removeObject(forKeyAsync key: String, completion block: PINCacheObjectBlock) {
        operationQueue.scheduleOperation({
            self.removeObject(forKey: key)

            
                block(self, key, nil)
        }, with: .low)
    }

    func trim(toDateAsync trimDate: Date, completion block: PINCacheBlock) {
        operationQueue.scheduleOperation({
            self.trim(to: trimDate)

            
                block(self)
        }, with: .low)
    }

    func removeExpiredObjectsAsync(_ block: PINCacheBlock) {
        operationQueue.scheduleOperation({
            self.removeExpiredObjects()

            
                block(self)
        }, with: .low)
    }

    func removeAllObjectsAsync(_ block: PINCacheBlock) {
        operationQueue.scheduleOperation({
            self.removeAllObjects()

            
                block(self)
        }, with: .low)
    }

// MARK: - Public Synchronous Methods -
    func containsObject(forKey key: String) -> Bool {
        if key == "" {
            return false
        }

        lock()
        let containsObject = dictionary[key] != nil
        unlock()
        return containsObject
    }

    func object(forKey key: String) -> Any? {
        if key == "" {
            return nil
        }

        let now = Date()
        lock()
        var object: Any? = nil
        // If the cache should behave like a TTL cache, then only fetch the object if there's a valid ageLimit and  the object is still alive
        let ageLimit = (ageLimits[key] as? NSNumber)?.doubleValue ?? self.ageLimit
        if !ttlCache ||
            ageLimit <= 0 ||
            fabs(Float(createdDates[key]?.timeIntervalSince(now) ?? 0.0)) < Float(ageLimit) {
            object = dictionary[key]
        }
        unlock()

        if object != nil {
            lock()
            accessDates[key] = now
            unlock()
        }

        return object
    }

    subscript(key: String) -> Any? {
        get {
            return object(forKey: key)
        }
        set {
            if let object = newValue {
                setObject(object, forKey: key)
            } else {
                removeObject(forKey: key)
            }
        }
    }

    func setObject(_ object: Any?, forKey key: String) {
        setObject(object, forKey: key, withCost: 0)
    }

    func setObject(_ object: Any?, forKey key: String, withAgeLimit ageLimit: TimeInterval) {
        setObject(object, forKey: key, withCost: 0, ageLimit: ageLimit)
    }

    func setObject(_ object: Any?, forKeyedSubscript key: String) {
    
    }

    func setObject(_ object: Any?, forKey key: String, withCost cost: UInt) {
        setObject(object, forKey: key, withCost: cost, ageLimit: 0.0)
    }

    func setObject(_ object: Any?, forKey key: String, withCost cost: UInt, ageLimit: TimeInterval) {
        assert(ageLimit <= 0.0 || (ageLimit > 0.0 && ttlCache), "ttlCache must be set to YES if setting an object-level age limit.")

        if key == "" || object == nil {
            return
        }

        lock()
        let willAddObjectBlock = self.willAddObjectBlock
        let didAddObjectBlock = self.didAddObjectBlock
        let costLimit = self.costLimit
        unlock()

        if willAddObjectBlock != nil {
            willAddObjectBlock?(self, key, object)
        }

        lock()
        let oldCost = costs[key] as? NSNumber
        if oldCost != nil {
            totalCost -= Int(oldCost?.uintValue ?? 0)
        }

        let now = Date()
        if let object = object {
            dictionary[key] = object
        }
        createdDates[key] = now
        accessDates[key] = now
        costs[key] = NSNumber(value: cost)

        if ageLimit > 0.0 {
            ageLimits[key] = NSNumber(value: ageLimit)
        } else {
            ageLimits.removeValue(forKey: key)
        }

        totalCost += cost
        unlock()

        if didAddObjectBlock != nil {
            didAddObjectBlock?(self, key, object)
        }

        if costLimit > 0 {
            trimToCost(byDate: costLimit)
        }
    }

    func removeObject(forKey key: String) {
        if key == "" {
            return
        }

        removeObjectAndExecuteBlocks(forKey: key)
    }

    func trim(to trimDate: Date) {
        if trimDate == nil {
            return
        }

        if trimDate.isEqual(to: Date.distantPast) {
            removeAllObjects()
            return
        }

        trimMemory(to: trimDate)
    }

    func removeAllObjects() {
        lock()
        let willRemoveAllObjectsBlock = self.willRemoveAllObjectsBlock
        let didRemoveAllObjectsBlock = self.didRemoveAllObjectsBlock
        unlock()

        if willRemoveAllObjectsBlock != nil {
            willRemoveAllObjectsBlock?(self)
        }

        lock()
        dictionary.removeAll()
        createdDates.removeAll()
        accessDates.removeAll()
        costs.removeAll()
        ageLimits.removeAll()

        totalCost = 0
        unlock()

        if didRemoveAllObjectsBlock != nil {
            didRemoveAllObjectsBlock?(self)
        }

    }

// MARK: - Public Thread Safe Accessors -

    func lock() {
        let result = os_unfair_lock_lock(&lock)
        assert(result == 0, "Failed to lock PINMemoryCache \(self). Code: \(result)")
    }

    func unlock() {
        let result = os_unfair_lock_unlock(&lock)
        assert(result == 0, "Failed to unlock PINMemoryCache \(self). Code: \(result)")
    }
}

extension PINMemoryCache {
    func containsObject(forKey key: String, block: PINMemoryCacheContainmentBlock) {
        containsObject(forKeyAsync: key, completion: block)
    }

    func object(forKey key: String, block: PINMemoryCacheObjectBlock?) {
        if let block = block {
            object(forKeyAsync: key, completion: block)
        }
    }

    func setObject(_ object: Any?, forKey key: String, block: PINMemoryCacheObjectBlock?) {
        setObjectAsync(object, forKey: key, completion: block)
    }

    func setObject(_ object: Any?, forKey key: String, withCost cost: UInt, block: PINMemoryCacheObjectBlock?) {
        setObjectAsync(object, forKey: key, withCost: cost, completion: block)
    }

    func removeObject(forKey key: String, block: PINMemoryCacheObjectBlock?) {
        removeObject(forKeyAsync: key, completion: block)
    }

    func trim(to date: Date, block: PINMemoryCacheBlock?) {
        trim(toDateAsync: date, completion: block)
    }

    func trim(toCost cost: UInt, block: PINMemoryCacheBlock?) {
        if let block = block {
            trim(toCostAsync: cost, completion: block)
        }
    }

    func trimToCost(byDate cost: UInt, block: PINMemoryCacheBlock?) {
        if let block = block {
            trimToCost(byDateAsync: cost, completion: block)
        }
    }

    func removeAllObjects(_ block: PINMemoryCacheBlock?) {
        removeAllObjectsAsync(block)
    }

    func enumerateObjects(with block: PINMemoryCacheObjectBlock, completionBlock: PINMemoryCacheBlock?) {
        if let completionBlock = completionBlock {
            enumerateObjects(withBlockAsync: { cache, key, object, stop in
                if (cache is PINMemoryCache) {
                    let memoryCache = cache as? PINMemoryCache
                    block(memoryCache!, key, object)
                }
            }, completionBlock: completionBlock)
        }
    }

    func setTtl(_ ttlCache: Bool) {
        lock()
        _ttlCache = ttlCache
        unlock()
    }
}

// MARK: - Deprecated

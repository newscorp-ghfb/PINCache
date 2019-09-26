//  Converted to Swift 5.1 by Swiftify v5.1.27756 - https://objectivec2swift.com/
//  PINCache is a modified version of TMCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

//  PINCache is a modified version of PINCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

import Foundation
import PINOperation

private let PINCachePrefix = "com.pinterest.PINCache"
private let PINCacheSharedName = "PINCacheShared"

/**
 `PINCache` is a thread safe key/value store designed for persisting temporary objects that are expensive to
 reproduce, such as downloaded data or the results of slow processing. It is comprised of two self-similar
 stores, one in memory (<PINMemoryCache>) and one on disk (<PINDiskCache>).

 `PINCache` itself actually does very little; its main function is providing a front end for a common use case:
 a small, fast memory cache that asynchronously persists itself to a large, slow disk cache. When objects are
 removed from the memory cache in response to an "apocalyptic" event they remain in the disk cache and are
 repopulated in memory the next time they are accessed. `PINCache` also does the tedious work of creating a
 dispatch group to wait for both caches to finish their operations without blocking each other.

 The parallel caches are accessible as public properties (<memoryCache> and <diskCache>) and can be manipulated
 separately if necessary. See the docs for <PINMemoryCache> and <PINDiskCache> for more details.

 @warning when using in extension or watch extension, define PIN_APP_EXTENSIONS=1
 */

@objc
@objcMembers
public class PINCache: NSObject, PINCaching, PINCacheObjectSubscripting {
    // MARK: -
    /// @name Core

    /**
     Synchronously retrieves the total byte count of the <diskCache> on the shared disk queue.
     */

    var diskByteCount: Int {
        var byteCount = 0

        diskCache.synchronouslyLockFileAccessWhileExecuting({ diskCache in
            byteCount = diskCache.byteCount
        })

        return byteCount
    }
    /**
     The underlying disk cache, see <PINDiskCache> for additional configuration and trimming options.
     */
    private(set) var diskCache: PINDiskCache
    /**
     The underlying memory cache, see <PINMemoryCache> for additional configuration and trimming options.
     */
    private(set) var memoryCache: PINMemoryCache

    // MARK: - Lifecycle
    /// @name Initialization

    convenience override init() {
        fatalError("PINCache must be initialized with a name. Call initWithName: instead.")
    }

    /**
     Multiple instances with the same name are *not* allowed and can *not* safely
     access the same data on disk. Also used to create the <diskCache>.
     Initializer allows you to override default NSKeyedArchiver/NSKeyedUnarchiver serialization for <diskCache>.
     You must provide both serializer and deserializer, or opt-out to default implementation providing nil values.

     @see name
     @param name The name of the cache.
     @param rootPath The path of the cache on disk.
     @param serializer   A block used to serialize object before writing to disk. If nil provided, default NSKeyedArchiver serialized will be used.
     @param deserializer A block used to deserialize object read from disk. If nil provided, default NSKeyedUnarchiver serialized will be used.
     @param keyEncoder A block used to encode key(filename). If nil provided, default url encoder will be used
     @param keyDecoder A block used to decode key(filename). If nil provided, default url decoder will be used
     @param ttlCache Whether or not the cache should behave as a TTL cache.
     @result A new cache with the specified name.
     */
    required init(name: String,
                  rootPath: String = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? "",
                  serializer: PINDiskCacheSerializerBlock? = nil,
                  deserializer: PINDiskCacheDeserializerBlock? = nil,
                  keyEncoder: PINDiskCacheKeyEncoderBlock? = nil,
                  keyDecoder: PINDiskCacheKeyDecoderBlock? = nil,
                  ttlCache: Bool = false) {
        
        precondition(optionallyEqual(serializer, deserializer),
                     "PINDiskCache must be initialized with a serializer AND deserializer.")
        precondition(optionallyEqual(keyEncoder, keyDecoder),
                     "PINDiskCache must be initialized with a keyEncoder AND keyDecoder.")
        
        super.init()
        self.name = name
        
        //10 may actually be a bit high, but currently much of our threads are blocked on empyting the trash. Until we can resolve that, lets bump this up.
        operationQueue = PINOperationQueue(maxConcurrentOperations: 10)
        diskCache = PINDiskCache(name: name,
                                 prefix: PINDiskCachePrefix,
                                 rootPath: rootPath,
                                 serializer: serializer,
                                 deserializer: deserializer,
                                 keyEncoder: keyEncoder,
                                 keyDecoder: keyDecoder,
                                 operationQueue: operationQueue,
                                 ttlCache: ttlCache)
        
        memoryCache = PINMemoryCache(name: self.name, operationQueue: operationQueue, ttlCache: ttlCache)
    }

    public let name: String
    private var operationQueue: PINOperationQueue

    // MARK: - Initialization -

    override public var description: String {
        return String(format: "%@.%@.%p", PINCachePrefix, name, self)
    }

    // MAKE: Singleton instance
    @objc(sharedCache)
    static let shared: PINCache = PINCache()

    // MARK: - Public Asynchronous Methods -
    public func containsObject(forKeyAsync key: String, completion block: PINCacheObjectContainmentBlock) {
        precondition(!key.isEmpty, "Empty key not allowed")
        if key.isEmpty { return }
        
        operationQueue.scheduleOperation {
            let containsObject = self.containsObject(forKey: key)
            block(containsObject)
        }
    }

//#pragma clang diagnostic push
//#pragma clang diagnostic ignored "-Wshadow"
    public func object(forKeyAsync key: String, completion block: PINCacheObjectBlock) {

        operationQueue.scheduleOperation({
            self.memoryCache.object(forKeyAsync: key) { memoryCache, memoryCacheKey, memoryCacheObject in
                if memoryCacheObject != nil {
                    // Update file modification date. TODO: make this a separate method?
                    self.diskCache.fileURL(forKeyAsync: memoryCacheKey) { key, fileURL in
                    }
                    self.operationQueue.scheduleOperation({
                        block(self, memoryCacheKey, memoryCacheObject)
                    })
                } else {
                    self.diskCache.object(forKeyAsync: memoryCacheKey) { diskCache, diskCacheKey, diskCacheObject in

                        self.memoryCache.setObjectAsync(diskCacheObject, forKey: diskCacheKey, completion: nil)

                        self.operationQueue.scheduleOperation({
                            block(self, diskCacheKey, diskCacheObject)
                        })
                    }
                }
            }
        })
    }

    public func setObjectAsync(_ object: Any, forKey key: String, cost: UInt = 0, ageLimit: TimeInterval = 0.0, completion block: PINCacheObjectBlock? = nil) {
        let group = PINOperationGroup.asyncOperationGroup(with: operationQueue)

        group.addOperation({
            self.memoryCache.setObject(object, forKey: key, withCost: cost, ageLimit: ageLimit)
        })
        group.addOperation({
            self.diskCache.setObject(object, forKey: key, withAgeLimit: ageLimit)
        })

        if let block = block {
            group.setCompletion {
                block(self, key, object)
            }
        }

        group.start()
    }

    public func removeObject(forKeyAsync key: String, completion block: PINCacheObjectBlock? = nil) {
        let group = PINOperationGroup.asyncOperationGroup(with: operationQueue)

        group.addOperation({
            self.memoryCache.removeObject(forKey: key)
        })
        group.addOperation({
            self.diskCache.removeObject(forKey: key)
        })

        if let block = block {
            group.setCompletion  {
                block(self, key, nil)
            }
        }

        group.start()
    }
    
    public func removeAllObjectsAsync(_ block: PINCacheBlock? = nil) {
        let group = PINOperationGroup.asyncOperationGroup(with: operationQueue)
        
        group.addOperation({
            self.memoryCache.removeAllObjects()
        })
        group.addOperation({
            self.diskCache.removeAllObjects()
        })
        
        if let block = block {
            group.setCompletion  {
                block(self)
            }
        }
        
        group.start()
    }

    public func trim(toDateAsync date: Date, completion block: PINCacheBlock? = nil) {
        let group = PINOperationGroup.asyncOperationGroup(with: operationQueue)

        group.addOperation({
            self.memoryCache.trim(to: date)
        })
        group.addOperation({
            self.diskCache.trim(to: date)
        })
        
        if let block = block {
            group.setCompletion  {
                block(self)
            }
        }

        group.start()
    }

    public func removeExpiredObjectsAsync(_ block: PINCacheBlock? = nil) {
        let group = PINOperationGroup.asyncOperationGroup(with: operationQueue)

        group.addOperation({
            self.memoryCache.removeExpiredObjects()
        })
        group.addOperation({
            self.diskCache.removeExpiredObjects()
        })
        
        if let block = block {
            group.setCompletion  {
                block(self)
            }
        }

        group.start()
    }

    // MARK: - Public Synchronous Accessors -

    public func containsObject(forKey key: String) -> Bool {
        return memoryCache.containsObject(forKey: key) || diskCache.containsObject(forKey: key)
    }

    public func object(forKey key: String) -> Any? {
        var object: Any? = nil
        
        object = memoryCache[key]
        
        if object != nil {
            // Update file modification date.
            diskCache.updateModifyTimeForfileURL(forKeyAsync: key)
        } else {
            object = diskCache[key]
            memoryCache.setObject(object, forKey: key)
        }

        return object
    }

    public func setObject(_ object: Any, forKey key: String, withCost cost: UInt = 0, ageLimit: TimeInterval = 0.0) {

        memoryCache.setObject(object, forKey: key, withCost: cost, ageLimit: ageLimit)
        diskCache.setObject(object, forKey: key, withAgeLimit: ageLimit)
    }

    @inlinable @inline(__always)
    public subscript(key: String) -> Any? {
        get {
            return self[key]
        }
        set {
            guard let obj = newValue else {
                removeObject(forKey: key as String)
                return
            }
            self.setObject(obj, forKey: key)
        }
    }

    public func removeObject(forKey key: String) {
        precondition(!key.isEmpty, "Empty key unsupported")
        memoryCache.removeObject(forKey: key)
        diskCache.removeObject(forKey: key)
    }

    public func trim(to date: Date) {
        memoryCache.trim(to: date)
        diskCache.trim(to: date)
    }

    public func removeExpiredObjects() {
        memoryCache.removeExpiredObjects()
        diskCache.removeExpiredObjects()
    }

    public func removeAllObjects() {
        memoryCache.removeAllObjects()
        diskCache.removeAllObjects()
    }
}

// MARK: Deprecated
@objc(Deprecated)
extension PINCache {
    @available(*, deprecated, renamed: "containsObject(forKeyAsync:completion:)")
    func containsObject(forKey key: String, block: PINCacheObjectContainmentBlock) {
        containsObject(forKeyAsync: key, completion: block)
    }
    
    @available(*, deprecated, renamed: "object(forKeyAsync:completion:)")
    func object(forKey key: String, block: PINCacheObjectBlock) {
        object(forKeyAsync: key, completion: block)
    }
    
    @available(*, deprecated, renamed: "setObjectAsync(_:forKey:completion:)")
    func setObject(_ object: Cacheable, forKey key: String, block: PINCacheObjectBlock? = nil) {
        setObjectAsync(object, forKey: key, completion: block)
    }
    
    @available(*, deprecated, renamed: "setObjectAsync(_:forKey:withCost:completion:)")
    func setObject(_ object: Cacheable, forKey key: String, withCost cost: UInt, block: PINCacheObjectBlock? = nil) {
        setObjectAsync(object, forKey: key, cost: cost, completion: block)
    }
    
    @available(*, deprecated, renamed: "removeObject(forKeyAsync:completion:)")
    func removeObject(forKey key: String, block: PINCacheObjectBlock? = nil) {
        removeObject(forKeyAsync: key, completion: block)
    }
    
    @available(*, deprecated, renamed: "trim(toDateAsync:completion:)")
    func trim(to date: Date, block: PINCacheBlock? = nil) {
        trim(toDateAsync: date, completion: block)
    }
    
    @available(*, deprecated, renamed: "removeAllObjectsAsync(_:)")
    func removeAllObjects(_ block: PINCacheBlock? = nil) {
        removeAllObjectsAsync(block)
    }
}

internal func optionallyEqual<L,R>(_ l:L?, _ r:R?) -> Bool {
    switch (l, r) {
    case (.none, .none), (.some, .some): return true
    default: return false
    }
}

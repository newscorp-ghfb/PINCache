//  Converted to Swift 5.1 by Swiftify v5.1.27756 - https://objectivec2swift.com/
//  PINCache is a modified version of TMCache
//  Modifications by Garrett Moon
//  Copyright (c) 2015 Pinterest. All rights reserved.

import Foundation
import PINOperation
import OSLog

/*
 #import <pthread.h>
 #import <sys/xattr.h>
 import sys
 */

#if canImport(UIKit)
import UIKit
#endif

enum PINDiskCacheError : Int, Error {
    case readFailure = -1000
    case writeFailure = -1001
}

/**
 A callback block which provides the cache, key and object as arguments
 */
typealias PINDiskCacheObjectBlock = (PINDiskCache, String, Cacheable?) -> Void
/**
 A callback block which provides the key and fileURL of the object
 */
typealias PINDiskCacheFileURLBlock = (String, URL?) -> Void
/**
 A callback block used for enumeration which provides the key and fileURL of the object plus a stop flag that
 may be flipped by the caller.
 */
typealias PINDiskCacheFileURLEnumerationBlock = (String, URL?, inout Bool ) -> Void
/**
 A callback block which provides a BOOL value as argument
 */
typealias PINDiskCacheContainsBlock = (Bool) -> Void
/**
 *  A block used to serialize object before writing to disk
 *
 *  @param object Object to serialize
 *  @param key The key associated with the object
 *
 *  @return Serialized object representation
 */
typealias PINDiskCacheSerializerBlock = (Cacheable, String) -> Data
/**
 *  A block used to deserialize objects
 *
 *  @param data Serialized object data
 *  @param key The key associated with the object
 *
 *  @return Deserialized object
 */
typealias PINDiskCacheDeserializerBlock = (Data, String) -> Cacheable
/**
 *  A block used to encode keys
 *
 *  @param decodedKey Original/decoded key
 *
 *  @return encoded key
 */
typealias PINDiskCacheKeyEncoderBlock = (String) -> String
/**
 *  A block used to decode keys
 *
 *  @param encodedKey An encoded key
 *
 *  @return decoded key
 */
typealias PINDiskCacheKeyDecoderBlock = (String) -> String


typealias PINCacheDiskClosure = PINCacheClosure<PINDiskCache>

// MARK: - Deprecated

/**
 A callback block which provides only the cache as an argument
 */
typealias PINDiskCacheBlock = (PINDiskCache) -> Void

#if canImport(UIKit)
import UIKit
#endif

@inlinable @inline(__always)
func LOG_ERROR(_ error: Error?,
               file: String = #file,
                function: String = #function,
                line: Int = #line) {
    guard let error = error else { return }
    
    let path: String = (#file as NSString).lastPathComponent
    if #available(iOSApplicationExtension 12.0, *) {
        os_log(.error, "%s (%d) %s ERROR: %s", path, line, function, error.localizedDescription)
    } else {
        // Fallback on earlier versions
        NSLog("%s (%d) %s ERROR: %s", path, line, function, error.localizedDescription)
    }
}

@inlinable @inline(__always)
func PINDiskCacheException(_ exception: NSException?) {
    guard let exception = exception else { return }
    assertionFailure(exception.reason ?? exception.description)
}

let PINDiskCacheAgeLimitAttributeName = "com.pinterest.PINDiskCache.ageLimit".cString(using: .utf8)

@objc
public extension NSErrorDomain {
    static
    let PINDiskCacheErrorDomain: NSErrorDomain = "com.pinterest.PINDiskCache"
}

@objc
public extension NSError.UserInfoKey {
static let PINDiskCacheErrorReadFailureCodeKey: NSError.UserInfoKey = "PINDiskCacheErrorReadFailureCodeKey"
static let PINDiskCacheErrorWriteFailureCodeKey: NSError.UserInfoKey = "PINDiskCacheErrorWriteFailureCodeKey"
}

let PINDiskCachePrefix = "com.pinterest.PINDiskCache"
private let PINDiskCacheSharedName = "PINDiskCacheShared"
private let PINDiskCacheOperationIdentifierTrimToDate = "PINDiskCacheOperationIdentifierTrimToDate"
private let PINDiskCacheOperationIdentifierTrimToSize = "PINDiskCacheOperationIdentifierTrimToSize"
private let PINDiskCacheOperationIdentifierTrimToSizeByDate = "PINDiskCacheOperationIdentifierTrimToSizeByDate"

enum PINDiskCacheCondition : Int {
    case notReady = 0
    case ready = 1
}

private var PINDiskTrimmingSizeCoalescingBlock: PINOperationDataCoalescingBlock = { existingSize, newSize in
    var result: ComparisonResult? = nil
    if let newSize = newSize as? NSNumber,
        let existingSize = existingSize as? NSNumber {
        result = existingSize.compare(newSize)
    }
    return (result == .orderedDescending) ? newSize : existingSize
}

private var PINDiskTrimmingDateCoalescingBlock: PINOperationDataCoalescingBlock = { existingDate, newDate in
    var result: ComparisonResult? = nil
    if let newDate = newDate as? Date,
       let existingDate = existingDate as? Date {
        result = existingDate.compare(newDate)
    }
    return (result == .orderedDescending) ? newDate : existingDate
}

/**
 `PINDiskCache` is a thread safe key/value store backed by the file system. It accepts any object conforming
 to the `Cacheable` protocol, which includes the basic Foundation data types and collection classes and also
 many UIKit classes, notably `UIImage`. All work is performed on a serial queue shared by all instances in
 the app, and archiving is handled by `NSKeyedArchiver`. This is a particular advantage for `UIImage` because
 it skips `UIImagePNGRepresentation()` and retains information like scale and orientation.

 The designated initializer for `PINDiskCache` is <initWithName:>. The <name> string is used to create a directory
 under Library/Caches that scopes disk access for this instance. Multiple instances with the same name are *not* 
 allowed as they would conflict with each other.

 Unless otherwise noted, all properties and methods are safe to access from any thread at any time. All blocks
 will cause the queue to wait, making it safe to access and manipulate the actual cache files on disk for the
 duration of the block.

 Because this cache is bound by disk I/O it can be much slower than <PINMemoryCache>, although values stored in
 `PINDiskCache` persist after application relaunch. Using <PINCache> is recommended over using `PINDiskCache`
 by itself, as it adds a fast layer of additional memory caching while still writing to disk.

 All access to the cache is dated so the that the least-used objects can be trimmed first. Setting an optional
 <ageLimit> will trigger a GCD timer to periodically to trim the cache with <trimToDate:>.
 */
var _sharedTrashURL: URL?

public
class PINDiskCache: NSObject, PINCaching, PINCacheObjectSubscripting {
    private var serializer: PINDiskCacheSerializerBlock?
    private var deserializer: PINDiskCacheDeserializerBlock?
    private var keyEncoder: PINDiskCacheKeyEncoderBlock?
    private var keyDecoder: PINDiskCacheKeyDecoderBlock?

// MARK: - Class

    /**
     @param rootPath The path for where the cache should be stored.
     @param prefix The prefix for the cache name.
     @param name The name of the cache.
     @result The full URL of the cache.
     */
    class func cacheURL(withRootPath rootPath: String, prefix: String, name: String) -> URL {
        let pathComponent = "\(prefix).\(name)"
        return (NSURL.fileURL(withPathComponents: [rootPath, pathComponent]))!
    }

// MARK: - Properties
    /// @name Core

    /**
     The prefix to the name of this cache, used to create a directory under Library/Caches and also appearing in stack traces.
     */
    private(set) var prefix: String
    /**
     The URL of the directory used by this cache, usually `Library/Caches/com.pinterest.PINDiskCache.(name)`

     @warning Do not interact with files under this URL except in <lockFileAccessWhileExecutingBlock:> or
     <synchronouslyLockFileAccessWhileExecutingBlock:>.
     */
    private(set) var cacheURL: URL?
    /**
     The total number of bytes used on disk, as reported by `NSURLTotalFileAllocatedSizeKey`.

     @warning This property should only be read from a call to <synchronouslyLockFileAccessWhileExecutingBlock:> or
     its asynchronous equivalent <lockFileAccessWhileExecutingBlock:>

     For example:

        // some background thread

        __block NSUInteger byteCount = 0;

        [_diskCache synchronouslyLockFileAccessWhileExecutingBlock:^(PINDiskCache *diskCache) {
            byteCount = diskCache.byteCount;
        }];
     */
    private(set) var byteCount = 0
    /**
     The maximum number of bytes allowed on disk. This value is checked every time an object is set, if the written
     size exceeds the limit a trim call is queued. Defaults to `0.0`, meaning no practical limit.

     */
    #if swift(>=5.1)
    @Locked
    @usableFromInline
    // 50 MB by default
    internal var _byteLimit = 50 * 1024 * 1024
    #else
    @usableFromInline
    // 50 MB by default
    internal var _byteLimit = 50 * 1024 * 1024;
    #endif
    
    @usableFromInline
    var byteLimit: Int {
        @inlinable @inline(__always)
        get {
            var byteLimit: Int

            lock()
            byteLimit = _byteLimit
            unlock()

            return byteLimit
        }
        set(byteLimit) {
            operationQueue.scheduleOperation({
                self.lock()
                self._byteLimit = byteLimit
                self.unlock()
                if byteLimit > 0 {
                    self.trimDiskToSize(byDate: byteLimit)
                }
            }, with: .high)
        }
    }
    /**
     The maximum number of seconds an object is allowed to exist in the cache. Setting this to a value
     greater than `0.0` will start a recurring GCD timer with the same period that calls <trimToDate:>.
     Setting it back to `0.0` will stop the timer. Defaults to `0.0`, meaning no limit.

     */

    // 30 days by default
    private var _ageLimit: TimeInterval =  60 * 60 * 24 * 30
    var ageLimit: TimeInterval {
        get {
            var ageLimit: TimeInterval

            lock()
            ageLimit = _ageLimit
            unlock()

            return ageLimit
        }
        set(ageLimit) {
            operationQueue.scheduleOperation({
                self.lock()
                self._ageLimit = ageLimit
                self.unlock()
                self.operationQueue.scheduleOperation({
                    self.trimToAgeLimitRecursively()
                }, with: .low)
            }, with: .high)
        }
    }
    /**
     The writing protection option used when writing a file on disk. This value is used every time an object is set.
     NSDataWritingAtomic and NSDataWritingWithoutOverwriting are ignored if set
     Defaults to NSDataWritingFileProtectionNone.

     @warning Only new files are affected by the new writing protection. If you need all files to be affected,
     you'll have to purge and set the objects back to the cache

     Only available on iOS
     */
#if os(iOS)

    private var _writingProtectionOption: NSData.WritingOptions?
    var writingProtectionOption: NSData.WritingOptions {
        get {
            var option: NSData.WritingOptions

            lock()
            if let _writingProtectionOption = _writingProtectionOption {
                option = _writingProtectionOption
            }
            unlock()

            return option
        }
        set(writingProtectionOption) {
            operationQueue.scheduleOperation({
                let option = NSData.WritingOptions(rawValue: NSData.WritingOptions.fileProtectionMask.rawValue & writingProtectionOption.rawValue)
                self.lock()
                self.writingProtectionOptionSet = true
                self._writingProtectionOption = option
                self.unlock()
            }, with: .high)
        }
    }
#endif

    /**
     If ttlCache is YES, the cache behaves like a ttlCache. This means that once an object enters the
     cache, it only lives as long as self.ageLimit. This has the following implications:
        - Accessing an object in the cache does not extend that object's lifetime in the cache
        - When attempting to access an object in the cache that has lived longer than self.ageLimit,
          the cache will behave as if the object does not exist

     @note If an object-level age limit is set via one of the @c -setObject:forKey:withAgeLimit methods,
     that age limit overrides self.ageLimit. The overridden object age limit could be greater or less
     than self.agelimit but must be greater than zero.

     */

    private var _ttlCache = false
    var ttlCache: Bool {
        var isTTLCache: Bool

        lock()
        isTTLCache = _ttlCache
        unlock()

        return isTTLCache
    }
// MARK: - Event Blocks
    /// @name Event Blocks

    /**
     A block to be executed just before an object is added to the cache. The queue waits during execution.
     */

    private var _willAddObjectBlock: PINDiskCacheObjectBlock?
    var willAddObjectBlock: PINDiskCacheObjectBlock? {
        get {
            var block: PINDiskCacheObjectBlock? = nil

            lock()
            block = _willAddObjectBlock
            unlock()

            return block!
        }
        set(block) {
            operationQueue.scheduleOperation({
                self.lock()
                self._willAddObjectBlock = block
                self.unlock()
            }, with: .high)
        }
    }
    /**
     A block to be executed just before an object is removed from the cache. The queue waits during execution.
     */

    private var _willRemoveObjectBlock: PINDiskCacheObjectBlock?
    var willRemoveObjectBlock: PINDiskCacheObjectBlock? {
        get {
            var block: PINDiskCacheObjectBlock? = nil

            lock()
            block = _willRemoveObjectBlock
            unlock()

            return block!
        }
        set(block) {
            operationQueue.scheduleOperation({
                self.lock()
                self._willRemoveObjectBlock = block
                self.unlock()
            }, with: .high)
        }
    }
    /**
     A block to be executed just before all objects are removed from the cache as a result of <removeAllObjects:>.
     The queue waits during execution.
     */

    private var _willRemoveAllObjectsBlock: PINCacheBlock?
    var willRemoveAllObjectsBlock: PINCacheBlock? {
        get {
            var block: PINCacheBlock? = nil

            lock()
            block = _willRemoveAllObjectsBlock
            unlock()

            return block!
        }
        set(block) {
            operationQueue.scheduleOperation({
                self.lock()
                self._willRemoveAllObjectsBlock = block
                self.unlock()
            }, with: .high)
        }
    }
    /**
     A block to be executed just after an object is added to the cache. The queue waits during execution.
     */

    private var _didAddObjectBlock: PINDiskCacheObjectBlock?
    var didAddObjectBlock: PINDiskCacheObjectBlock? {
        get {
            var block: PINDiskCacheObjectBlock? = nil

            lock()
            block = _didAddObjectBlock
            unlock()

            return block!
        }
        set(block) {
            operationQueue.scheduleOperation({
                self.lock()
                self._didAddObjectBlock = block
                self.unlock()
            }, with: .high)
        }
    }
    /**
     A block to be executed just after an object is removed from the cache. The queue waits during execution.
     */

    private var _didRemoveObjectBlock: PINDiskCacheObjectBlock?
    var didRemoveObjectBlock: PINDiskCacheObjectBlock? {
        get {
            var block: PINDiskCacheObjectBlock? = nil

            lock()
            block = _didRemoveObjectBlock
            unlock()

            return block!
        }
        set(block) {
            operationQueue.scheduleOperation({
                self.lock()
                self._didRemoveObjectBlock = block
                self.unlock()
            }, with: .high)
        }
    }
    /**
     A block to be executed just after all objects are removed from the cache as a result of <removeAllObjects:>.
     The queue waits during execution.
     */

    private var _didRemoveAllObjectsBlock: PINCacheBlock?
    var didRemoveAllObjectsBlock: PINCacheBlock? {
        get {
            var block: PINCacheBlock? = nil

            lock()
            block = _didRemoveAllObjectsBlock
            unlock()

            return block!
        }
        set(block) {
            operationQueue.scheduleOperation({
                self.lock()
                self._didRemoveAllObjectsBlock = block
                self.unlock()
            }, with: .high)
        }
    }
// MARK: - Lifecycle
    /// @name Initialization

    /**
     A shared cache.

     @result The shared singleton cache instance.
     */
    private(set) var sharedCache: PINDiskCache?

    /**
     Empties the trash with `DISPATCH_QUEUE_PRIORITY_BACKGROUND`. Does not use lock.
     */
    class func emptyTrash() {
        PINDiskCache.sharedTrashQueue().async(execute: {
            let trashURLMaybe: URL?
            
            // If _sharedTrashURL is unset, there's nothing left to do because it hasn't been accessed and therefore items haven't been added to it.
            // If it is set, we can just remove it.
            // We also need to nil out _sharedTrashURL so that a new one will be created if there's an attempt to move a new file to the trash.
            PINDiskCache.sharedLock().lock()
            if _sharedTrashURL != nil {
                trashURLMaybe = _sharedTrashURL
                _sharedTrashURL = nil
            } else {
                trashURLMaybe = nil
            }
            PINDiskCache.sharedLock().unlock()
            
            guard let trashURL = trashURLMaybe else { return }
            do {
                try FileManager.default.removeItem(at: trashURL)
            } catch {
                LOG_ERROR(error)
            }
        })
    }

    convenience override init() {
        fatalError("PINDiskCache must be initialized without a name. Call initWithName: instead.")
    }

    /**
     The designated initializer allowing you to override default NSKeyedArchiver/NSKeyedUnarchiver serialization.

     @see name
     @param name The name of the cache.
     @param prefix The prefix for the cache name. Defaults to com.pinterest.PINDiskCache
     @param rootPath The path of the cache.
     @param serializer   A block used to serialize object. If nil provided, default NSKeyedArchiver serialized will be used.
     @param deserializer A block used to deserialize object. If nil provided, default NSKeyedUnarchiver serialized will be used.
     @param keyEncoder A block used to encode key(filename). If nil provided, default url encoder will be used
     @param keyDecoder A block used to decode key(filename). If nil provided, default url decoder will be used
     @param operationQueue A PINOperationQueue to run asynchronous operations
     @param ttlCache Whether or not the cache should behave as a TTL cache.
     @result A new cache with the specified name.
     */
    required init(name: String,
                  prefix: String = PINDiskCachePrefix,
                  rootPath: String = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0],
                  serializer: PINDiskCacheSerializerBlock? = nil,
                  deserializer: PINDiskCacheDeserializerBlock? = nil,
                  keyEncoder: PINDiskCacheKeyEncoderBlock? = nil,
                  keyDecoder: PINDiskCacheKeyDecoderBlock? = nil,
                  operationQueue: PINOperationQueue = PINOperationQueue.shared(),
                  ttlCache: Bool) {
    
        precondition((serializer == nil) == (deserializer == nil), "PINDiskCache must be initialized with a serializer AND deserializer.")
        precondition((keyEncoder == nil) == (keyDecoder == nil), "PINDiskCache must be initialized with a encoder AND decoder.")

        super.init()
        
        self.name = name
        self.prefix = prefix
        self.operationQueue = operationQueue
        _ttlCache = ttlCache

        #if os(iOS)
            writingProtectionOptionSet = false
            // This is currently the default for files, but we'd rather not write it if it's unspecified.
            writingProtectionOption = .completeFileProtectionUntilFirstUserAuthentication
        #endif

            metadata = [:]
            diskStateKnown = false

        cacheURL = PINDiskCache.cacheURL(withRootPath: rootPath, prefix: self.prefix, name: self.name)

            //setup serializers
            if serializer != nil {
                self.serializer = serializer
            } else {
                self.serializer = defaultSerializer()
            }

            if deserializer != nil {
                self.deserializer = deserializer
            } else {
                self.deserializer = defaultDeserializer()
            }

            //setup key encoder/decoder
            self.keyEncoder = keyEncoder ?? defaultKeyEncoder()
            self.keyDecoder = keyDecoder ?? defaultKeyDecoder()

            pthread_cond_init(&diskWritableCondition, nil)
            pthread_cond_init(&diskStateKnownCondition, nil)

            //we don't want to do anything without setting up the disk cache, but we also don't want to block init, it can take a while to initialize. This must *not* be done on _operationQueue because other operations added may hold the lock and fill up the queue.
            DispatchQueue.global(qos: .default).async(execute: {
                self.lock()
                self._locked_createCacheDirectory()
                self.unlock()
                self.initializeDiskProperties()
            })
    }

// MARK: - Asynchronous Methods
    /// @name Asynchronous Methods
    /**
     Locks access to ivars and allows safe interaction with files on disk. This method returns immediately.

     @warning Calling synchronous methods on the diskCache inside this block will likely cause a deadlock.

     @param block A block to be executed when a lock is available.
     */
    func lockFileAccessWhileExecutingBlockAsync(_ block: PINCacheBlock) {
        operationQueue.scheduleOperation({
            self.lockForWriting()
            block(self)
            self.unlock()
        }, with: .low)
    }

    /**
     Retrieves the object for the specified key. This method returns immediately and executes the passed
     block as soon as the object is available.

     @param key The key associated with the requested object.
     @param block A block to be executed serially when the object is available.
     */
    func object(forKeyAsync key: String, completion block: PINDiskCacheObjectBlock) {
        operationQueue.scheduleOperation({
            var fileURL: URL? = nil
            weak var object = self.object(forKey: key, fileURL: &fileURL)

            block(self, key, object)
        }, with: .low)
    }

    /**
     Retrieves the fileURL for the specified key without actually reading the data from disk. This method
     returns immediately and executes the passed block as soon as the object is available.

     @warning Access is protected for the duration of the block, but to maintain safe disk access do not
     access this fileURL after the block has ended.

     @warning The PINDiskCache lock is held while block is executed. Any synchronous calls to the diskcache
     or a cache which owns the instance of the disk cache are likely to cause a deadlock. This is why the block is
     *not* passed the instance of the disk cache. You should also avoid doing extensive work while this
     lock is held.

     @param key The key associated with the requested object.
     @param block A block to be executed serially when the file URL is available.
     */
    func fileURL(forKeyAsync key: String, completion block: PINDiskCacheFileURLBlock) {
        operationQueue.scheduleOperation({
            let fileURL = self.fileURL(forKey: key)

            self.lockForWriting()
            block(key, fileURL)
            self.unlock()
        }, with: .low)
    }
        
    func updateModifyTimeForfileURL(forKeyAsync key: String, completion block: PINDiskCacheFileURLBlock? = nil) {
         operationQueue.scheduleOperation({
            let fileURL = self.fileURL(forKey: key, updateFileModificationDate: !self.ttlCache)

            if let block = block {
                self.lockForWriting()
                block(key, fileURL)
                self.unlock()
            }
         }, with: .low)
     }

    /**
     Stores an object in the cache for the specified key. This method returns immediately and executes the
     passed block as soon as the object has been stored.

     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param block A block to be executed serially after the object has been stored, or nil.
     */
    func setObjectAsync(_ object: NSCoding?, forKey key: String, completion block: PINDiskCacheObjectBlock) {
        setObjectAsync(object, forKey: key, withAgeLimit: 0.0, completion: block)
    }

    /**
     Stores an object in the cache for the specified key and age limit. This method returns immediately and executes the
     passed block as soon as the object has been stored.

     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param ageLimit The age limit (in seconds) to associate with the object. An age limit <= 0 means there is no object-level age limit and the cache-level TTL
                     will be used for this object.
     @param block A block to be executed serially after the object has been stored, or nil.
     */
    func setObjectAsync(_ object: NSCoding?, forKey key: String, withAgeLimit ageLimit: TimeInterval, completion block: PINDiskCacheObjectBlock?) {
        operationQueue.scheduleOperation({
            var fileURL: URL? = nil
            self.setObject(object, forKey: key, withAgeLimit: ageLimit, fileURL: &fileURL)

                block?(self, key, object)
        }, with: .low)
    }

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
    func setObjectAsync(_ object: NSCoding?, forKey key: String, withCost cost: UInt, completion block: PINCacheObjectBlock?) {
        setObjectAsync(object, forKey: key, completion: block)
    }

    /**
     Stores an object in the cache for the specified key and the specified memory cost and age limit. If the cost causes the total
     to go over the <memoryCache.costLimit> the cache is trimmed (oldest objects first). This method returns immediately
     and executes the passed block after the object has been stored, potentially in parallel with other blocks
     on the <concurrentQueue>.

     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param cost An amount to add to the <memoryCache.totalCost>.
     @param ageLimit The age limit (in seconds) to associate with the object. An age limit <= 0 means there is no object-level age limit and the cache-level TTL will be used for
                     this object.
     @param block A block to be executed concurrently after the object has been stored, or nil.
     */
    func setObjectAsync(_ object: NSCoding?, forKey key: String, withCost cost: UInt, ageLimit: TimeInterval, completion block: PINCacheObjectBlock? = nil) {
        setObjectAsync(object, forKey: key, withAgeLimit: ageLimit, completion: block as? PINDiskCacheObjectBlock)
    }

    /**
     Removes the object for the specified key. This method returns immediately and executes the passed block
     as soon as the object has been removed.

     @param key The key associated with the object to be removed.
     @param block A block to be executed serially after the object has been removed, or nil.
     */
    func removeObject(forKeyAsync key: String, completion block: PINDiskCacheObjectBlock) {
        operationQueue.scheduleOperation({
            var fileURL: URL? = nil
            self.removeObject(forKey: key, fileURL: &fileURL)

            
                block(self, key, nil)
        }, with: .low)
    }

    /**
     Removes objects from the cache, largest first, until the cache is equal to or smaller than the specified byteCount.
     This method returns immediately and executes the passed block as soon as the cache has been trimmed.

     @param byteCount The cache will be trimmed equal to or smaller than this size.
     @param block A block to be executed serially after the cache has been trimmed, or nil.
     */
    func trim(toSizeAsync trimByteCount: Int, completion block: PINCacheClosure<PINDiskCache>) {
        let operation = { data in
                self.trim(toSize: Int((data as? NSNumber)?.uintValue ?? 0))
            } as? PINOperationBlock

        let completion =  {
                block(self)
            }

        operationQueue.scheduleOperation(operation, with: .low, identifier: PINDiskCacheOperationIdentifierTrimToSize, coalescingData: NSNumber(value: UInt(trimByteCount)), dataCoalescingBlock: PINDiskTrimmingSizeCoalescingBlock, completion: completion)
    }

    /**
     Removes objects from the cache, ordered by date (least recently used first), until the cache is equal to or smaller
     than the specified byteCount. This method returns immediately and executes the passed block as soon as the cache has
     been trimmed.

     @param byteCount The cache will be trimmed equal to or smaller than this size.
     @param block A block to be executed serially after the cache has been trimmed, or nil.

     @note This will not remove objects that have been added via one of the @c -setObject:forKey:withAgeLimit methods.
     */
    func trimToSize(byDateAsync trimByteCount: UInt, completion block: PINCache) {
        let operation = { data in
                self.trimToSize(byDate: Int((data as? NSNumber)?.uintValue ?? 0))
            } as? PINOperationBlock

        let completion = {
                block(self)
            }

        operationQueue.scheduleOperation(operation, with: .low, identifier: PINDiskCacheOperationIdentifierTrimToSizeByDate, coalescingData: NSNumber(value: UInt(trimByteCount)), dataCoalescingBlock: PINDiskTrimmingSizeCoalescingBlock, completion: completion)
    }

    /**
     Loops through all objects in the cache (reads and writes are suspended during the enumeration). Data is not actually
     read from disk, the `object` parameter of the block will be `nil` but the `fileURL` will be available.
     This method returns immediately.

     @param block A block to be executed for every object in the cache.
     @param completionBlock An optional block to be executed after the enumeration is complete.

     @warning The PINDiskCache lock is held while block is executed. Any synchronous calls to the diskcache
     or a cache which owns the instance of the disk cache are likely to cause a deadlock. This is why the block is
     *not* passed the instance of the disk cache. You should also avoid doing extensive work while this
     lock is held.

     */
    func enumerateObjects(withBlockAsync block: PINDiskCacheFileURLEnumerationBlock, completionBlock: PINCacheBlock) {
        operationQueue.scheduleOperation({
            self.enumerateObjects(with: block)
            completionBlock(self)
        }, with: .low)
    }

// MARK: - Synchronous Methods
    /// @name Synchronous Methods

    /**
     Locks access to ivars and allows safe interaction with files on disk. This method only returns once the block
     has been run.

     @warning Calling synchronous methods on the diskCache inside this block will likely cause a deadlock.

     @param block A block to be executed when a lock is available.
     */
    func synchronouslyLockFileAccessWhileExecuting(_ block: PINCacheClosure<PINDiskCache>) {
        lockForWriting()
        block(self)
        unlock()
    }

    /**
     Retrieves the object for the specified key. This method blocks the calling thread until the
     object is available.

     @see objectForKeyAsync:completion:
     @param key The key associated with the object.
     @result The object for the specified key.
     */
    public func object(forKey key: String) -> Any? {
        return object(forKey: key, fileURL: nil)
    }

    /**
     Retrieves the file URL for the specified key. This method blocks the calling thread until the
     url is available. Do not use this URL anywhere except with <lockFileAccessWhileExecutingBlock:>. This method probably
     shouldn't even exist, just use the asynchronous one.

     @see fileURLForKeyAsync:completion:
     @param key The key associated with the object.
     @result The file URL for the specified key.
     */
    func fileURL(forKey key: String) -> URL {
        // Don't update the file modification time, if self is a ttlCache
        return fileURL(forKey: key, updateFileModificationDate: !ttlCache)
    }

    /**
     Stores an object in the cache for the specified key. This method blocks the calling thread until
     the object has been stored.

     @see setObjectAsync:forKey:completion:
     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     */
    public func setObject(_ object: Any?, forKey key: String) {
        setObject(object, forKey: key, withAgeLimit: 0.0)
    }

    /**
     Stores an object in the cache for the specified key and age limit. This method blocks the calling thread until
     the object has been stored.

     @see setObjectAsync:forKey:completion:
     @param object An object to store in the cache.
     @param key A key to associate with the object. This string will be copied.
     @param ageLimit The age limit (in seconds) to associate with the object. An age limit <= 0 means there is
                     no object-level age limit and the cache-level TTL will be used for this object.
     */
    func setObject(_ object: Any?, forKey key: String, withAgeLimit ageLimit: TimeInterval = 0.0) {
        setObject(object, forKey: key, withAgeLimit: ageLimit, fileURL: nil)
    }

    /**
     Removes objects from the cache, largest first, until the cache is equal to or smaller than the
     specified byteCount. This method blocks the calling thread until the cache has been trimmed.

     @see trimToSizeAsync:
     @param byteCount The cache will be trimmed equal to or smaller than this size.
     */
    func trim(toSize trimByteCount: Int) {
        if trimByteCount == 0 {
            removeAllObjects()
            return
        }

        trimDisk(toSize: trimByteCount)
    }

    /**
     Removes objects from the cache, ordered by date (least recently used first), until the cache is equal to or
     smaller than the specified byteCount. This method blocks the calling thread until the cache has been trimmed.

     @see trimToSizeByDateAsync:
     @param byteCount The cache will be trimmed equal to or smaller than this size.

     @note This will not remove objects that have been added via one of the @c -setObject:forKey:withAgeLimit methods.
     */
    func trimToSize(byDate trimByteCount: Int) {
        if trimByteCount == 0 {
            removeAllObjects()
            return
        }

        trimDiskToSize(byDate: trimByteCount)
    }

    /**
     Loops through all objects in the cache (reads and writes are suspended during the enumeration). Data is not actually
     read from disk, the `object` parameter of the block will be `nil` but the `fileURL` will be available.
     This method blocks the calling thread until all objects have been enumerated.

     @see enumerateObjectsWithBlockAsync:completionBlock
     @param block A block to be executed for every object in the cache.

     @warning Do not call this method within the event blocks (<didRemoveObjectBlock>, etc.)
     Instead use the asynchronous version, <enumerateObjectsWithBlock:completionBlock:>.

     @warning The PINDiskCache lock is held while block is executed. Any synchronous calls to the diskcache
     or a cache which owns the instance of the disk cache are likely to cause a deadlock. This is why the block is
     *not* passed the instance of the disk cache. You should also avoid doing extensive work while this
     lock is held.

     */
    func enumerateObjects(with block: PINDiskCacheFileURLEnumerationBlock) {
        lockAndWaitForKnownState()
        let now = Date()

        for let key in metadata {
            guard let key = key as? String else {
                continue
            }
            let fileURL = encodedFileURL(forKey: key)
            // If the cache should behave like a TTL cache, then only fetch the object if there's a valid ageLimit and the object is still alive
            let createdDate = metadata[key].createdDate
            let ageLimit = metadata[key].ageLimit > 0.0 ? metadata[key].ageLimit : self.ageLimit
            if !ttlCache || ageLimit <= 0 || (createdDate != nil && fabs(Float(createdDate?.timeIntervalSince(now) ?? 0.0)) < Float(ageLimit)) {
                var stop = false
                block(key, fileURL, &stop)
                if stop {
                    break
                }
            }
        }
        unlock()
    }

    public let name: String
    private var operationQueue: PINOperationQueue
    private var metadata: [String : PINDiskCacheMetadata] = [:]
    private var diskWritableCondition = pthread_cond_t()
    private var diskWritable = false
    private var diskStateKnownCondition = pthread_cond_t()
    private var diskStateKnown = false

    private let lock = Lock()

    #if os(iOS)
    private var writingProtectionOption: Bool = NSData.WritingOptions.completeFileProtectionUntilFirstUserAuthentication
     private var writingProtectionOptionSet = false
    #endif

// MARK: - Initialization -
    deinit {
        let result = pthread_mutex_destroy((&mutex)!)
        assert(result == 0, String(format: "Failed to destroy lock in PINMemoryCache %p. Code: %d", self, result))
        pthread_cond_destroy(&diskWritableCondition)
        pthread_cond_destroy(&diskStateKnownCondition)
    }

    override public var description: String {
        return String(format: "%@.%@.%p", PINDiskCachePrefix, name, self)
    }

    @objc(sharedCache)
    public static let shared: PINDiskCache = PINDiskCache(name: PINDiskCacheSharedName)

// MARK: - Private Methods -
    func encodedFileURL(forKey key: String) -> URL {
        if key.count == 0 {
            return nil
        }

        //Significantly improve performance by indicating that the URL will *not* result in a directory.
        //Also note that accessing _cacheURL is safe without the lock because it is only set on init.
        return (cacheURL?.appendingPathComponent(encodedString(key), isDirectory: false))!
    }

    func key(forEncodedFileURL url: URL) -> String {
        let fileName = url.lastPathComponent
        if fileName == "" {
            return ""
        }

        return decodedString(fileName)
    }

    func encodedString(_ string: String) -> String {
        return keyEncoder?(string)
    }

    func decodedString(_ string: String) -> String {
        return keyDecoder?(string)
    }

    func defaultSerializer() -> PINDiskCacheSerializerBlock {
        return { object, key in
            if #available(iOS 11.0, macOS 10.13, tvOS 11.0, watchOS 4.0, *) {
                do {
                    return try NSKeyedArchiver.archivedData(withRootObject: object,
                                                            requiringSecureCoding: false)
                } catch {
                    LOG_ERROR(error)
                    return nil
                }
            } else {
                return NSKeyedArchiver.archivedData(withRootObject: object)
            }
        }
    }

    func defaultDeserializer() -> PINDiskCacheDeserializerBlock {
        return { data, key in
            return NSKeyedUnarchiver.unarchiveObject(with: data)
        }
    }

    static let defaultKeyEncoderCharsToEscape = ".:/%"

    func defaultKeyEncoder() -> PINDiskCacheKeyEncoderBlock {
        return { decodedKey in
            if decodedKey == nil || decodedKey!.isEmpty {
                return ""
            }

            if #available(macOS 10.9, iOS 7.0, tvOS 9.0, watchOS 2.0, *) {
                let encodedString = decodedKey.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: ".:/%").inverted)
                return encodedString ?? ""
            } else {
            //#pragma clang diagnostic push
            //#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                let escapedString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, decodedKey as CFString, nil, PINDiskCache.defaultKeyEncoderCharsToEscape, CFStringBuiltInEncodings.UTF8)
            //#pragma clang diagnostic pop

                return escapedString as String
            }
        }
    }

    func defaultKeyDecoder() -> PINDiskCacheKeyEncoderBlock {
        return { encodedKey in
            if encodedKey == nil || encodedKey!.isEmpty {
                return ""
            }

            if #available(macOS 10.9, iOS 7.0, tvOS 9.0, watchOS 2.0, *) {
                return encodedKey.removingPercentEncoding ?? ""
            } else {
            //#pragma clang diagnostic push
            //#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                let unescapedString = CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault, encodedKey as CFString, "", CFStringBuiltInEncodings.UTF8)
            //#pragma clang diagnostic pop
                return unescapedString as String
            }
        }
    }

// MARK: - Private Trash Methods -
    static var trashQueue: DispatchQueue?

    class func sharedTrashQueue() -> DispatchQueue {

        // `dispatch_once()` call was converted to a static variable initializer

        return trashQueue!
    }

    static var sharedLockVar: NSLock?

    class func sharedLock() -> NSLock {
        // `dispatch_once()` call was converted to a static variable initializer
        return sharedLockVar!
    }

    class func sharedTrashURL() -> URL {
        var trashURL: URL? = nil

        PINDiskCache.sharedLock().lock()
        if _sharedTrashURL == nil {
            let uniqueString = ProcessInfo.processInfo.globallyUniqueString
            _sharedTrashURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uniqueString, isDirectory: true)

            var error: Error? = nil
            do {
                if let _sharedTrashURL = _sharedTrashURL {
                    try FileManager.default.createDirectory(at: _sharedTrashURL, withIntermediateDirectories: true, attributes: nil)
                }
            } catch {
            }
            LOG_ERROR(error)
        }
        trashURL = _sharedTrashURL
        PINDiskCache.sharedLock().unlock()

        return trashURL!
    }

    @discardableResult
    class func moveItemAtURL(toTrash itemURL: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: itemURL.path) {
            return false
        }

        var error: Error? = nil
        let uniqueString = ProcessInfo.processInfo.globallyUniqueString
        let uniqueTrashURL = PINDiskCache.sharedTrashURL().appendingPathComponent(uniqueString, isDirectory: false)
        var moved = false
        do {
            try FileManager.default.moveItem(at: itemURL, to: uniqueTrashURL)
            moved = true
        } catch {
        }
        LOG_ERROR(error)
        return moved
    }

// MARK: - Private Queue Methods -
    func _locked_createCacheDirectory() -> Bool {
        var created = false
        if FileManager.default.fileExists(atPath: cacheURL?.path ?? "") == false {
            var error: Error? = nil
            do {
                if let cacheURL = cacheURL {
                    created = try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true, attributes: nil)
                }
            } catch {
            }
            LOG_ERROR(error)
        }



        // while this may not be true if success is false, it's better than deadlocking later.
        diskWritable = true
        pthread_cond_broadcast(&diskWritableCondition)

        return created
    }

    static let resourceKeysVar: [AnyHashable]? = nil

    class func resourceKeys() -> [AnyHashable] {

        // `dispatch_once()` call was converted to a static variable initializer

        return resourceKeysVar ?? []
    }

    /**
     * @return File size in bytes.
     */
    @discardableResult
    func _locked_initializeDiskProperties(forFile fileURL: URL, fileKey: String) -> Int {
        var error: Error? = nil

        var dictionary: [URLResourceKey : Any]? = nil
        do {
            dictionary = try (fileURL as NSURL).resourceValues(forKeys: PINDiskCache.resourceKeys())
        } catch {
        }
        LOG_ERROR(error)

        if metadata[fileKey] == nil {
            metadata[fileKey] = PINDiskCacheMetadata()
        }

        let createdDate = dictionary?[URLResourceKey.creationDateKey] as? Date
        if createdDate != nil && fileKey != "" {
            metadata[fileKey].createdDate = createdDate
        }

        let lastModifiedDate = dictionary?[URLResourceKey.contentModificationDateKey] as? Date
        if lastModifiedDate != nil && fileKey != "" {
            metadata[fileKey].lastModifiedDate = lastModifiedDate
        }

        let fileSize = dictionary?[URLResourceKey.totalFileAllocatedSizeKey] as? NSNumber
        if fileSize != nil {
            metadata[fileKey].size = fileSize
        }

        if ttlCache {
            var ageLimit: TimeInterval
            let res = getxattr(PINDiskCacheFileSystemRepresentation(fileURL), PINDiskCacheAgeLimitAttributeName, &ageLimit, MemoryLayout<TimeInterval>.size, 0, 0)
            if Int(res) > 0 {
                metadata[fileKey].ageLimit = ageLimit
            } else if Int(res) == -1 {
                // Ignore if the extended attribute was never recorded for this file.
                if errno != ENOATTR {
                    var userInfo: [NSErrorUserInfoKey : id]? = nil
                    if let PINDiskCacheErrorReadFailureCodeKey = PINDiskCacheErrorReadFailureCodeKey {
                        userInfo = [
                        PINDiskCacheErrorReadFailureCodeKey: NSNumber(value: errno)
                    ] as? [NSErrorUserInfoKey : id]
                    }
                    error = NSError(domain: PINDiskCacheErrorDomain, code: PINDiskCacheError.readFailure.rawValue, userInfo: userInfo)
                    LOG_ERROR(error)
                }
            }
        }

        return Int(fileSize?.uintValue ?? 0)
    }

    func initializeDiskProperties() {
        var byteCount = 0

        var error: Error? = nil

        lock()
        var files: [URL]? = nil
        do {
            if let cacheURL = cacheURL {
                files = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: PINDiskCache.resourceKeys(), options: .skipsHiddenFiles)
            }
        } catch {
        }
        unlock()

        LOG_ERROR(error)

        for fileURL in files ?? [] {
            let fileKey = key(forEncodedFileURL: fileURL)
            // Continually grab and release lock while processing files to avoid contention
            lock()
            if metadata[fileKey] == nil {
                byteCount += _locked_initializeDiskProperties(forFile: fileURL, fileKey: fileKey)
            }
            unlock()
        }

        lock()
        if byteCount > 0 {
            self.byteCount = byteCount
        }

        if byteLimit > 0 && self.byteCount > byteLimit {
            trimToSize(byDateAsync: byteLimit)
        }

        if ttlCache {
            removeExpiredObjectsAsync(nil)
        }

        diskStateKnown = true
        pthread_cond_broadcast(&diskStateKnownCondition)
        unlock()
    }

    func asynchronouslySetFileModificationDate(_ date: Date, for fileURL: URL) {
        operationQueue.scheduleOperation({
            self.lockForWriting()
            self._locked_setFileModificationDate(date, for: fileURL)
            self.unlock()
        }, with: .low)
    }

    func _locked_setFileModificationDate(_ date: Date, for fileURL: URL) -> Bool {
        if date == nil || fileURL == nil {
            return false
        }

        var error: Error? = nil
        var success = false
        do {
            try FileManager.default.setAttributes([
                        FileAttributeKey.modificationDate: date
                    ], ofItemAtPath: fileURL.path)
            success = true
        } catch {
        }
        LOG_ERROR(error)

        return success
    }

    func asynchronouslySetAgeLimit(_ ageLimit: TimeInterval, for fileURL: URL) {
        operationQueue.scheduleOperation({
            self.lockForWriting()
            self._locked_setAgeLimit(ageLimit, for: fileURL)
            self.unlock()
        }, with: .low)
    }

    func _locked_setAgeLimit(_ ageLimit: TimeInterval, for fileURL: URL) -> Bool {
        var ageLimit = ageLimit
        if fileURL == nil {
            return false
        }

        var error: Error? = nil
        if ageLimit <= 0.0 {
            if removexattr(PINDiskCacheFileSystemRepresentation(fileURL), PINDiskCacheAgeLimitAttributeName, 0) != 0 {
                // Ignore if the extended attribute was never recorded for this file.
                if errno != ENOATTR {
                    var userInfo: [NSErrorUserInfoKey : id]? = nil
                    if let PINDiskCacheErrorWriteFailureCodeKey = PINDiskCacheErrorWriteFailureCodeKey {
                        userInfo = [
                        PINDiskCacheErrorWriteFailureCodeKey: NSNumber(value: errno)
                    ] as? [NSErrorUserInfoKey : id]
                    }
                    error = NSError(domain: PINDiskCacheErrorDomain, code: PINDiskCacheError.writeFailure.rawValue, userInfo: userInfo)
                    LOG_ERROR(error)
                }
            }
        } else {
            if setxattr(PINDiskCacheFileSystemRepresentation(fileURL), PINDiskCacheAgeLimitAttributeName, &ageLimit, MemoryLayout<TimeInterval>.size, 0, 0) != 0 {
                var userInfo: [NSErrorUserInfoKey : id]? = nil
                if let PINDiskCacheErrorWriteFailureCodeKey = PINDiskCacheErrorWriteFailureCodeKey {
                    userInfo = [
                    PINDiskCacheErrorWriteFailureCodeKey: NSNumber(value: errno)
                ] as? [NSErrorUserInfoKey : id]
                }
                error = NSError(domain: PINDiskCacheErrorDomain, code: PINDiskCacheError.writeFailure.rawValue, userInfo: userInfo)
                LOG_ERROR(error)
            }
        }

        if error == nil {
            let key = self.key(forEncodedFileURL: fileURL)
            if key != "" {
                metadata[key].ageLimit = ageLimit
            }
        }

        return Bool(!error!)
    }

    func removeFileAndExecuteBlocks(forKey key: String) -> Bool {
        let fileURL = encodedFileURL(forKey: key)

        // We only need to lock until writable at the top because once writable, always writable
        lockForWriting()
        if fileURL == nil || !FileManager.default.fileExists(atPath: fileURL.path) {
            unlock()
            return false
        }

        let willRemoveObjectBlock = self.willRemoveObjectBlock as? PINCacheObjectBlock
        if willRemoveObjectBlock != nil {
            unlock()
            willRemoveObjectBlock?(self, key, nil)
            lock()
        }

        let trashed = PINDiskCache.moveItemAtURL(toTrash: fileURL)
        if !trashed {
            unlock()
            return false
        }

        PINDiskCache.emptyTrash()

        let byteSize = metadata[key].size
        if byteSize != nil {
            byteCount = byteCount - Int(byteSize?.uintValue ?? 0) // atomic
        }

        metadata.removeValue(forKey: key)

        let didRemoveObjectBlock = self.didRemoveObjectBlock as? PINCacheObjectBlock
        if didRemoveObjectBlock != nil {
            unlock()
            self.didRemoveObjectBlock?(self, key, nil)
            lock()
        }

        unlock()

        return true
    }

    func trimDisk(toSize trimByteCount: Int) {
        var keysToRemove: [AnyHashable]? = nil

        lockForWriting()
        if byteCount > trimByteCount {
            keysToRemove = []

            let keysSortedBySize = (metadata as NSDictionary).keysSortedByValue(comparator: { obj1, obj2 in
                    return (obj1.size?.compare(size))!
                })

            var bytesSaved = 0
            for key in (keysSortedBySize as NSArray).reverseObjectEnumerator() {
                guard let key = key as? String else {
                    continue
                }
                // largest objects first
                keysToRemove?.append(key)
                let byteSize = metadata[key].size
                if byteSize != nil {
                    bytesSaved += Int(byteSize?.uintValue ?? 0)
                }
                if byteCount - bytesSaved <= trimByteCount {
                    break
                }
            }
        }
        unlock()

        for key in keysToRemove ?? [] {
            guard let key = key as? String else {
                continue
            }
            removeFileAndExecuteBlocks(forKey: key)
        }
    }

    // This is the default trimming method which happens automatically
    func trimDiskToSize(byDate trimByteCount: Int) {
        if isTTLCache {
            removeExpiredObjects()
        }

        var keysToRemove: [AnyHashable]? = nil

        lockForWriting()
        if byteCount > trimByteCount {
            keysToRemove = []

            // last modified represents last access.
            let keysSortedByLastModifiedDate = (metadata as NSDictionary).keysSortedByValue(comparator: { obj1, obj2 in
                    return (obj1.lastModifiedDate?.compare(lastModifiedDate))!
                })

            var bytesSaved = 0
            // objects accessed last first.
            for key in keysSortedByLastModifiedDate {
                keysToRemove?.append(key)
                let byteSize = metadata[key].size
                if byteSize != nil {
                    bytesSaved += Int(byteSize?.uintValue ?? 0)
                }
                if byteCount - bytesSaved <= trimByteCount {
                    break
                }
            }
        }
        unlock()

        for key in keysToRemove ?? [] {
            guard let key = key as? String else {
                continue
            }
            removeFileAndExecuteBlocks(forKey: key)
        }
    }

    func trimDisk(to trimDate: Date) {
        lockForWriting()
        let keysSortedByCreatedDate = (metadata as NSDictionary).keysSortedByValue(comparator: { obj1, obj2 in
                return (obj1.createdDate?.compare(createdDate))!
            })

        var keysToRemove: [AnyHashable] = []

        for key in keysSortedByCreatedDate {
            // oldest files first
            let createdDate = metadata[key].createdDate
            if createdDate == nil || metadata[key].ageLimit > 0.0 {
                continue
            }

            if createdDate?.compare(trimDate) == .orderedAscending {
                // older than trim date
                keysToRemove.append(key)
            } else {
                break
            }
        }
        unlock()

        for key in keysToRemove {
            guard let key = key as? String else {
                continue
            }
            removeFileAndExecuteBlocks(forKey: key)
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
        trim(toDateAsync: date)

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

    func containsObject(forKeyAsync key: String, completion block: PINDiskCacheContainsBlock) {
        operationQueue.scheduleOperation({
            block(self.containsObject(forKey: key))
        }, with: .low)
    }

    func trim(toDateAsync trimDate: Date, completion block: PINCacheBlock) {
        let operation = { data in
                if let data = data as? Date {
                    self.trim(to: data)
                }
            } as? PINOperationBlock

       let completion = {
                block(self)
            }

        operationQueue.scheduleOperation(operation, with: .low, identifier: PINDiskCacheOperationIdentifierTrimToDate, coalescingData: trimDate, dataCoalescingBlock: PINDiskTrimmingDateCoalescingBlock, completion: completion)
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
        lock()
        if metadata[key] != nil || diskStateKnown == false {
            var objectExpired = false
            if ttlCache && metadata[key].createdDate != nil {
                let ageLimit = metadata[key].ageLimit > 0.0 ? metadata[key].ageLimit : self.ageLimit
                objectExpired = ageLimit > 0 && fabs(Float(metadata[key].createdDate?.timeIntervalSince(Date()) ?? 0.0)) > Float(ageLimit)
            }
            unlock()
            return !objectExpired && fileURL(forKey: key, updateFileModificationDate: false) != nil
        }
        unlock()
        return false
    }

    subscript(key: String) -> Any? {
        return self[key]
    }

    func object(forKey key: String, fileURL outFileURL: inout URL) -> NSCoding? {
        var outFileURL = outFileURL
        lock()
        let containsKey = metadata[key] != nil || diskStateKnown == false
        unlock()

        if key == "" || !containsKey {
            return nil
        }

        weak var object: NSCoding? = nil
        let fileURL = encodedFileURL(forKey: key)

        let now = Date()
        lock()
        if ttlCache {
            if !diskStateKnown {
                if metadata[key] == nil {
                    let fileKey = self.key(forEncodedFileURL: fileURL)
                    _locked_initializeDiskProperties(forFile: fileURL, fileKey: fileKey)
                }
            }
        }

        let ageLimit = metadata[key].ageLimit > 0.0 ? metadata[key].ageLimit : self.ageLimit
        if !ttlCache || ageLimit <= 0 || fabs(Float(metadata[key].createdDate?.timeIntervalSince(now) ?? 0.0)) < Float(ageLimit) {
            // If the cache should behave like a TTL cache, then only fetch the object if there's a valid ageLimit and  the object is still alive

            let objectData = Data(contentsOfFile: fileURL.path)

            if objectData != nil {
                //Be careful with locking below. We unlock here so that we're not locked while deserializing, we re-lock after.
                unlock()
                // TODO: import SwiftTryCatch from https://github.com/eggheadgames/SwiftTryCatch
                SwiftTryCatch.try({
                    object = deserializer?(objectData, key)
                }, catch: { exception in
                    var error: Error? = nil
                    lock()
                    do {
                        try FileManager.default.removeItem(atPath: fileURL.path)
                    } catch {
                    }
                    unlock()
                    LOG_ERROR(error)
                    PINDiskCacheException(exception)
                }, finallyBlock: {
                })
                lock()
            }
            if object != nil {
                metadata[key].lastModifiedDate = now
                asynchronouslySetFileModificationDate(now, for: fileURL)
            }
        }
        unlock()

        if outFileURL != nil {
            outFileURL = fileURL
        }

        return object
    }

    /// Helper function to call fileURLForKey:updateFileModificationDate:
    func fileURL(forKey key: String, updateFileModificationDate: Bool) -> URL {
        if key == "" {
            return nil
        }

        let now = Date()
        var fileURL = encodedFileURL(forKey: key)

        lockForWriting()
        if fileURL.path != "" && FileManager.default.fileExists(atPath: fileURL.path) {
            if updateFileModificationDate {
                metadata[key].lastModifiedDate = now
                asynchronouslySetFileModificationDate(now, for: fileURL)
            }
        } else {
            fileURL = nil
        }
        unlock()
        return fileURL
    }

    public func setObject(_ object: Any?, forKeyedSubscript key: String) {
        if object == nil {
            removeObject(forKey: key as String)
        } else {
            self[key] = object
        }
    }

    func setObject(_ object: NSCoding?, forKey key: String, withAgeLimit ageLimit: TimeInterval, fileURL outFileURL: inout URL) {
        var outFileURL = outFileURL
        assert(ageLimit <= 0.0 || (ageLimit > 0.0 && ttlCache), "ttlCache must be set to YES if setting an object-level age limit.")

        if key == "" || object == nil {
            return
        }

        var writeOptions: NSData.WritingOptions = .atomic
#if os(iOS)
        if writingProtectionOptionSet {
            writeOptions.insert(writingProtectionOption)
        }
#endif

        // Remain unlocked here so that we're not locked while serializing.
        let data = serializer?(object, key)
        var fileURL: URL? = nil

        let byteLimit = self.byteLimit
        if data.count <= byteLimit || byteLimit == 0 {
            // The cache is large enough to fit this object (although we may need to evict others).
            fileURL = encodedFileURL(forKey: key)
        } else {
            // The cache isn't large enough to fit this object (even if all others were evicted).
            // We should not write it to disk because it will be deleted immediately after.
            if outFileURL != nil {
                outFileURL = nil
            }
            return
        }

        lockForWriting()
        let willAddObjectBlock = self.willAddObjectBlock as? PINCacheObjectBlock
        if willAddObjectBlock != nil {
            unlock()
            willAddObjectBlock?(self, key, object)
            lock()
        }

        var writeError: Error? = nil
        var written = false
        do {
            if let fileURL = fileURL {
                try data.write(to: fileURL, options: writeOptions)
                written = true
            }
        } catch let writeError {
        }
        LOG_ERROR(writeError)

        if written {
            if metadata[key] == nil {
                metadata[key] = PINDiskCacheMetadata()
            }

            var error: Error? = nil
            var values: [URLResourceKey : Any]? = nil
            do {
                values = try (fileURL as NSURL?)?.resourceValues(forKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .totalFileAllocatedSizeKey
            ])
            } catch {
            }
            LOG_ERROR(error)

            let diskFileSize = values?[.totalFileAllocatedSizeKey] as? NSNumber
            if diskFileSize != nil {
                let prevDiskFileSize = metadata[key].size
                if prevDiskFileSize != nil {
                    byteCount = byteCount - Int(prevDiskFileSize?.uintValue ?? 0)
                }
                metadata[key].size = diskFileSize
                byteCount = byteCount + Int(diskFileSize?.uintValue ?? 0) // atomic
            }
            let createdDate = values?[.creationDateKey] as? Date
            if createdDate != nil {
                metadata[key].createdDate = createdDate
            }
            let lastModifiedDate = values?[.contentModificationDateKey] as? Date
            if lastModifiedDate != nil {
                metadata[key].lastModifiedDate = lastModifiedDate
            }
            if let fileURL = fileURL {
                asynchronouslySetAgeLimit(ageLimit, for: fileURL)
            }
            if self.byteLimit > 0 && byteCount > self.byteLimit {
                trimToSize(byDateAsync: self.byteLimit)
            }
        } else {
            fileURL = nil
        }

        let didAddObjectBlock = self.didAddObjectBlock as? PINCacheObjectBlock
        if didAddObjectBlock != nil {
            unlock()
            didAddObjectBlock?(self, key, object)
            lock()
        }
        unlock()

        if outFileURL != nil {
            if let fileURL = fileURL {
                outFileURL = fileURL
            }
        }
    }

    func removeObject(forKey key: String) {
        removeObject(forKey: key, fileURL: nil)
    }

    func removeObject(forKey key: String, fileURL outFileURL: URL) {
        var outFileURL = outFileURL
        if key == "" {
            return
        }

        var fileURL: URL? = nil

        fileURL = encodedFileURL(forKey: key)

        removeFileAndExecuteBlocks(forKey: key)

        if outFileURL != nil {
            if let fileURL = fileURL {
                outFileURL = fileURL
            }
        }
    }

    func trim(to trimDate: Date) {
        if trimDate == nil {
            return
        }

        if trimDate.isEqual(to: Date.distantPast) {
            removeAllObjects()
            return
        }

        trimDisk(to: trimDate)
    }

    func removeExpiredObjects() {
        lockForWriting()
        let now = Date()
        var expiredObjectKeys: [String] = []
        (metadata as NSDictionary).enumerateKeysAndObjects({ key, obj, stop in
            let ageLimit = obj.ageLimit > 0.0 ? obj.ageLimit : self.ageLimit
            let expirationDate = obj.createdDate?.addingTimeInterval(ageLimit) as? Date
            if expirationDate?.compare(now) == .orderedAscending {
                // Expiration date has passed
                expiredObjectKeys.append(key)
            }
        })
        unlock()

        for key in expiredObjectKeys {
            //unlock, removeFileAndExecuteBlocksForKey handles locking itself
            removeFileAndExecuteBlocks(forKey: key)
        }
    }

    func removeAllObjects() {
        // We don't need to know the disk state since we're just going to remove everything.
        lockForWriting()
        let willRemoveAllObjectsBlock = self.willRemoveAllObjectsBlock
        if willRemoveAllObjectsBlock != nil {
            unlock()
            willRemoveAllObjectsBlock?(self)
            lock()
        }

        if let cacheURL = cacheURL {
            PINDiskCache.moveItemAtURL(toTrash: cacheURL)
        }
        PINDiskCache.emptyTrash()

        _locked_createCacheDirectory()

        metadata.removeAll()
        byteCount = 0 // atomic

        let didRemoveAllObjectsBlock = self.didRemoveAllObjectsBlock
        if didRemoveAllObjectsBlock != nil {
            unlock()
            didRemoveAllObjectsBlock?(self)
            lock()
        }

        unlock()
    }

// MARK: - Public Thread Safe Accessors -

#if os(iOS)
func writingProtectionOption() -> NSData.WritingOptions {
    var option: NSData.WritingOptions

    lock()
    option = writingProtectionOption
    unlock()

    return option
}

func setWritingProtectionOption(_ writingProtectionOption: NSData.WritingOptions) {
    operationQueue.scheduleOperation({
        let option = NSData.WritingOptions(rawValue: NSData.WritingOptions.fileProtectionMask.rawValue & writingProtectionOption.rawValue)

        self.lock()
        self.writingProtectionOptionSet = true
        self.writingProtectionOption() = option
        self.unlock()
    }, with: .high)
}

#endif
    func lockForWriting() {
        lock()

        // Lock if the disk isn't writable.
        if diskWritable == false {
            pthread_cond_wait(&diskWritableCondition, &mutex)
        }
    }

    func lockAndWaitForKnownState() {
        lock()

        // Lock if the disk state isn't known.
        if diskStateKnown == false {
            pthread_cond_wait(&diskStateKnownCondition, &mutex)
        }
    }

    
    func lock() {
        os_unfair_lock_lock(&_lock)
        assert(result == 0, "Failed to lock PINDiskCache \(self). Code: \(result)")
    }

    @inlinable @inline(__always)
    func unlock() {
        os_unfair_lock_unlock(&_lock)
        assert(result == 0, "Failed to unlock PINDiskCache \(self). Code: \(result)")
    }
}

extension PINDiskCache {
    func lockFileAccessWhileExecuting(_ block: PINCacheBlock?) {
        if let block = block {
            lockFileAccessWhileExecutingBlockAsync(block)
        }
    }

    func containsObject(forKey key: String, block: PINDiskCacheContainsBlock) {
        containsObject(forKeyAsync: key, completion: block)
    }

    func object(forKey key: String, block: PINDiskCacheObjectBlock?) {
        if let block = block {
            object(forKeyAsync: key, completion: block)
        }
    }

    func fileURL(forKey key: String, block: PINDiskCacheFileURLBlock?) {
        if let block = block {
            fileURL(forKeyAsync: key, completion: block)
        }
    }

    func setObject(_ object: NSCoding?, forKey key: String, block: PINDiskCacheObjectBlock?) {
        if let block = block {
            setObjectAsync(object, forKey: key, completion: block)
        }
    }

    func removeObject(forKey key: String, block: PINDiskCacheObjectBlock?) {
        if let block = block {
            removeObject(forKeyAsync: key, completion: block)
        }
    }

    func trim(to date: Date, block: PINDiskCacheBlock?) {
        if let block = block {
            trim(toDateAsync: date, completion: block)
        }
    }

    func trim(toSize byteCount: Int, block: PINDiskCacheBlock?) {
        if let block = block {
            trim(toSizeAsync: byteCount, completion: block)
        }
    }

    func trimToSize(byDate byteCount: Int, block: PINDiskCacheBlock?) {
        if let block = block {
            trim(toSizeAsync: byteCount, completion: block)
        }
    }

    func removeAllObjects(_ block: PINDiskCacheBlock?) {
        if let block = block {
            removeAllObjectsAsync(block)
        }
    }

    func enumerateObjects(with block: PINDiskCacheFileURLBlock, completionBlock: PINDiskCacheBlock?) {
        if let completionBlock = completionBlock {
            enumerateObjects(withBlockAsync: { key, fileURL, stop in
                block(key, fileURL)
            }, completionBlock: completionBlock)
        }
    }

    func setTtl(_ ttlCache: Bool) {
        operationQueue.scheduleOperation({
            self.lock()
            self._ttlCache = ttlCache
            self.unlock()
        }, with: .high)
    }
}

func PINDiskCacheFileSystemRepresentation(_ url: URL) -> UnsafePointer<Int8>? {
#if compiler(>=9)
    // -fileSystemRepresentation is available on macOS >= 10.9
    if #available(macOS 10.9, iOS 7.0, watchOS 2.0, tvOS 9.0, *) {
        return (url as NSURL).fileSystemRepresentation
    }
#endif
    return (url.path as NSString).cString(using: String.Encoding.utf8.rawValue)
}

class PINDiskCacheMetadata: NSObject {
    // When the object was added to the disk cache
    var createdDate: Date?
    // Last time the object was accessed
    var lastModifiedDate: Date?
    var size: NSNumber?
    // Age limit is used in conjuction with ttl
    var ageLimit: TimeInterval = 0.0
}

// TODO: Move me - testing lock wrappers
@usableFromInline
internal class Lock {
    @usableFromInline
    internal var _lock = os_unfair_lock_s()
    
    @usableFromInline
    internal var _mutex = pthread_mutex_t()
    
    @inlinable @inline(__always)
    internal func lock() {
        if #available(iOSApplicationExtension 10.0, *) {
            os_unfair_lock_lock(&_lock)
        } else {
            // Fallback on earlier versions
            let result = pthread_mutex_lock(&_mutex)
            assert(result == 0, "Failed to lock PINDiskCache \(self). Code: \(result)")
        }
    }
    
    @inlinable @inline(__always)
    internal func unlock() {
        if #available(iOSApplicationExtension 10.0, *) {
            os_unfair_lock_unlock(&_lock)
        } else {
            // Fallback on earlier versions
            let result = pthread_mutex_unlock(&_mutex)
            assert(result == 0, "Failed to unlock PINDiskCache \(self). Code: \(result)")
        }
    }
}

  @usableFromInline
  @propertyWrapper
  internal struct Locked<Value> {
      @usableFromInline
      internal var value: Value

      @usableFromInline
      let lock = Lock()

      @usableFromInline
      var wrappedValue: Value {
          get {
              defer { lock.unlock() }
              lock.lock()
              return value
          }
          set {
              lock.lock()
              value = newValue
              lock.unlock()
          }
      }

      @inlinable @inline(__always)
      init(wrappedValue initialValue: Value) {
          self.wrappedValue = initialValue
      }
  }

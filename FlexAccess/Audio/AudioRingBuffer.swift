import Foundation
import os

/// Thread-safe ring buffer for mono Float samples.
final class AudioRingBuffer {
    private var storage: [Float]
    private var readIndex  = 0
    private var writeIndex = 0
    private var count      = 0
    private var lock       = os_unfair_lock_s()

    nonisolated deinit {}   // prevent isolated-deinit crash on macOS 26 / Swift 6.1

    var capacity: Int { storage.count }

    init(capacitySamples: Int) {
        storage = Array(repeating: 0, count: Swift.max(1, capacitySamples))
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        readIndex = 0; writeIndex = 0; count = 0
        os_unfair_lock_unlock(&lock)
    }

    func availableToRead() -> Int {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return count
    }

    /// Write up to n samples. Returns number actually written.
    func write(from ptr: UnsafePointer<Float>, count n: Int) -> Int {
        guard n > 0 else { return 0 }
        os_unfair_lock_lock(&lock)
        let space   = storage.count - count
        let toWrite = Swift.min(space, n)
        guard toWrite > 0 else { os_unfair_lock_unlock(&lock); return 0 }
        let first   = Swift.min(toWrite, storage.count - writeIndex)
        storage.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.advanced(by: writeIndex).update(from: ptr, count: first)
            if first < toWrite {
                buf.baseAddress!.update(from: ptr.advanced(by: first), count: toWrite - first)
            }
        }
        writeIndex = (writeIndex + toWrite) % storage.count
        count += toWrite
        os_unfair_lock_unlock(&lock)
        return toWrite
    }

    /// Read up to n samples. Returns number actually read.
    func read(into ptr: UnsafeMutablePointer<Float>, count n: Int) -> Int {
        guard n > 0 else { return 0 }
        os_unfair_lock_lock(&lock)
        let toRead = Swift.min(count, n)
        guard toRead > 0 else { os_unfair_lock_unlock(&lock); return 0 }
        let first  = Swift.min(toRead, storage.count - readIndex)
        storage.withUnsafeBufferPointer { buf in
            ptr.update(from: buf.baseAddress!.advanced(by: readIndex), count: first)
            if first < toRead {
                ptr.advanced(by: first).update(from: buf.baseAddress!, count: toRead - first)
            }
        }
        readIndex = (readIndex + toRead) % storage.count
        count -= toRead
        os_unfair_lock_unlock(&lock)
        return toRead
    }
}

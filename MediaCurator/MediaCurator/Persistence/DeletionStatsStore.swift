import Foundation

/// Persists cumulative deletion stats (count + bytes freed).
/// Mirrors Android's `DeletionStatsStore`.
final class DeletionStatsStore {

    private let defaults: UserDefaults
    private enum Key {
        static let totalDeleted      = "stats_total_deleted"
        static let totalBytesFreed   = "stats_total_bytes_freed"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var totalDeleted: Int {
        get { defaults.integer(forKey: Key.totalDeleted) }
    }

    var totalBytesFreed: Int64 {
        get { Int64(bitPattern: UInt64(bitPattern: Int64(defaults.integer(forKey: Key.totalBytesFreed)))) }
    }

    func record(count: Int, bytes: Int64) {
        defaults.set(totalDeleted + count, forKey: Key.totalDeleted)
        // Store as two 32-bit ints to avoid sign/overflow issues with UserDefaults integer
        defaults.set(Int(totalBytesFreed + bytes), forKey: Key.totalBytesFreed)
    }

    func reset() {
        defaults.removeObject(forKey: Key.totalDeleted)
        defaults.removeObject(forKey: Key.totalBytesFreed)
    }
}

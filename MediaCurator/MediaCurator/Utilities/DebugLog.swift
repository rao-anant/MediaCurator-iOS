import Foundation
import os.log

/// Thin wrapper around os.log. Mirrors Android's `DebugLog`.
enum DebugLog {
    private static let logger = Logger(subsystem: "com.anant.MediaCurator", category: "app")

    static func i(_ tag: String, _ message: String) {
        logger.info("[\(tag)] \(message)")
    }

    static func d(_ tag: String, _ message: String) {
        logger.debug("[\(tag)] \(message)")
    }

    static func e(_ tag: String, _ message: String) {
        logger.error("[\(tag)] \(message)")
    }
}

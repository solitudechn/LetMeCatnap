import CatnapCore
import Foundation

/// App logger: console output (debug builds) plus a rotating file log.
///
/// A menu bar app has nowhere to surface errors, so a user who reports "it
/// stopped working" leaves no trace unless something is persisted. Writes are
/// serialized on a private queue and the file is rotated to `LetMeCatnap.1.log`
/// once it passes `maxFileSize`, so it can never grow without bound.
enum Log {
    private static let queue = DispatchQueue(label: "\(BundleIdentity.identifier).log")
    private static let maxFileSize = 1_000_000  // ~1 MB, roughly a month of use
    private static let folderName = "LetMeCatnap"

    /// `~/Library/Logs/LetMeCatnap/LetMeCatnap.log`
    static var fileURL: URL {
        let base =
            FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library", isDirectory: true)
        return
            base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("LetMeCatnap.log", isDirectory: false)
    }

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    /// Flush writes queued before application termination.
    static func flush() {
        queue.sync {}
    }

    // MARK: - Private

    /// Cached formatter. Allocating a `DateFormatter` costs about a millisecond,
    /// which is silly to pay per line, so it is created once and only ever used
    /// on `queue` — which serializes every write, satisfying the formatter's
    /// non-thread-safety for free.
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func write(_ level: String, _ message: String) {
        #if DEBUG
            print("[Catnap] \(message)")
        #endif
        queue.async {
            let stamp = stampFormatter.string(from: Date())
            append("\(stamp) [\(level)] \(message)\n")
        }
    }

    /// Runs on `queue` only.
    private static func append(_ line: String) {
        let fm = FileManager.default
        let url = fileURL

        try? fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let attributes = try? fm.attributesOfItem(atPath: url.path),
            let size = (attributes[.size] as? NSNumber)?.intValue,
            size > maxFileSize
        {
            let backup = url.deletingPathExtension().appendingPathExtension("1.log")
            try? fm.removeItem(at: backup)
            try? fm.moveItem(at: url, to: backup)
        }

        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            if (try? handle.seekToEnd()) != nil {
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: url)
        }
    }
}

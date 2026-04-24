//
//  UpdateLogger.swift
//  Demolish
//
//  Persistent logger for the auto-update flow. Writes to:
//    - os.Logger (viewable in Console.app, subsystem = bundle id, category = "update")
//    - Xcode console via print()
//    - A rotating file at ~/Library/Logs/Demolish/update.log
//
//  The updater bash script also writes to ~/Library/Logs/Demolish/updater.log so that
//  failures happening *after* the app quits (cp/rm/open) can still be diagnosed.
//

import Foundation
import os

final class UpdateLogger {
    static let shared = UpdateLogger()

    enum Level: String {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    private let logger: Logger
    private let queue = DispatchQueue(label: "com.demolish.updatelogger", qos: .utility)
    private let fileURL: URL
    private let maxBytes: UInt64 = 512 * 1024

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.demolish.app"
        self.logger = Logger(subsystem: subsystem, category: "update")

        let logsDir = UpdateLogger.logsDirectory()
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.fileURL = logsDir.appendingPathComponent("update.log")
    }

    static func logsDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/Demolish", isDirectory: true)
    }

    static var logFileURL: URL {
        return logsDirectory().appendingPathComponent("update.log")
    }

    static var updaterScriptLogFileURL: URL {
        return logsDirectory().appendingPathComponent("updater.log")
    }

    func info(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        write(.info, message: message(), file: file, line: line)
    }

    func warn(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        write(.warn, message: message(), file: file, line: line)
    }

    func error(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        write(.error, message: message(), file: file, line: line)
    }

    private func write(_ level: Level, message: String, file: String, line: Int) {
        let timestamp = dateFormatter.string(from: Date())
        let shortFile = (file as NSString).lastPathComponent
        let line = "[\(timestamp)] [\(level.rawValue)] [\(shortFile):\(line)] \(message)\n"

        switch level {
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warn:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
        print(line, terminator: "")

        queue.async { [fileURL, maxBytes] in
            UpdateLogger.appendToFile(line, at: fileURL, maxBytes: maxBytes)
        }
    }

    private static func appendToFile(_ line: String, at url: URL, maxBytes: UInt64) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64,
           size > maxBytes {
            let rotated = url.deletingPathExtension().appendingPathExtension("log.1")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: url, to: rotated)
        }

        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }

        guard let data = line.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

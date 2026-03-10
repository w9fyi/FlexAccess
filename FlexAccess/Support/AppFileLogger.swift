//
//  AppFileLogger.swift
//  FlexAccess
//
//  Writes log lines to ~/Downloads/FlexAccess/flexaccess.log.
//  Thread-safe — all writes serialised on a background queue.
//

import Foundation

final class AppFileLogger {
    static let shared = AppFileLogger()

    private let queue = DispatchQueue(label: "com.w9fyi.flexaccess.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private let maxBytes: UInt64 = 5 * 1024 * 1024   // 5 MB

    private init() {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlexAccess")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("flexaccess.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
    }

    func log(_ message: String) {
        queue.async { [weak self] in
            guard let self, let fh = self.fileHandle else { return }
            let line = "[\(self.timestamp())] \(message)\n"
            if let data = line.data(using: .utf8) {
                fh.write(data)
                if fh.offsetInFile > self.maxBytes {
                    fh.truncateFile(atOffset: 0)
                    fh.seekToEndOfFile()
                }
            }
        }
    }

    private func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withTime, .withColonSeparatorInTime, .withDashSeparatorInDate, .withFullDate]
        return f.string(from: Date())
    }
}

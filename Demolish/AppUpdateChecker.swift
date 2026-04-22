//
//  AppUpdateChecker.swift
//  Demolish
//
//  Checks GitHub Releases for new versions and handles download + install + relaunch.
//

import AppKit
import Combine
import Foundation

enum UpdateState: Equatable {
    case idle
    case checking
    case available(version: String, notes: String)
    case downloading(progress: Double)
    case installing
    case failed(String)

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.installing, .installing):
            return true
        case let (.available(v1, n1), .available(v2, n2)):
            return v1 == v2 && n1 == n2
        case let (.downloading(p1), .downloading(p2)):
            return p1 == p2
        case let (.failed(e1), .failed(e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

class AppUpdateChecker: ObservableObject {
    @Published var state: UpdateState = .idle

    private static let owner = "sloanal"
    private static let repo = "demolish"
    private let checkInterval: TimeInterval = 3600

    private var downloadURL: URL?
    private var downloadDelegate: UpdateDownloadDelegate?
    private var downloadSession: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var checkTimer: Timer?
    private var dismissedVersion: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    var updateVersion: String? {
        if case .available(let version, _) = state { return version }
        return nil
    }

    var isUpdateVisible: Bool {
        switch state {
        case .available, .downloading, .installing, .failed:
            return true
        default:
            return false
        }
    }

    func startChecking() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SIMULATE_UPDATE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.simulateUpdateAvailable()
            }
            return
        }
        #endif
        checkForUpdate()
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdate()
        }
    }

    func stopChecking() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    #if DEBUG
    func simulateUpdateAvailable() {
        downloadURL = nil
        dismissedVersion = nil
        state = .available(version: "99.0.0", notes: "Simulated update for UI testing.")
    }

    func simulateDownloading() {
        state = .downloading(progress: 0)
        simulateProgressTick(progress: 0)
    }

    private func simulateProgressTick(progress: Double) {
        guard case .downloading = state else { return }
        let next = min(progress + 0.05, 1.0)
        state = .downloading(progress: next)
        if next < 1.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.simulateProgressTick(progress: next)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.state = .installing
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.state = .available(version: "99.0.0", notes: "Simulated update for UI testing.")
                }
            }
        }
    }
    #endif

    // MARK: - Version check

    func checkForUpdate() {
        switch state {
        case .downloading, .installing:
            return
        default:
            break
        }

        state = .checking

        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            state = .idle
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleCheckResponse(data: data, response: response, error: error)
            }
        }.resume()
    }

    private func handleCheckResponse(data: Data?, response: URLResponse?, error: Error?) {
        guard error == nil,
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let data = data else {
            state = .idle
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            state = .idle
            return
        }

        let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let notes = (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard isNewerVersion(remoteVersion, than: currentVersion) else {
            state = .idle
            return
        }

        if remoteVersion == dismissedVersion {
            state = .idle
            return
        }

        let zipAsset = assets.first { asset in
            guard let name = asset["name"] as? String else { return false }
            return name.hasSuffix(".zip")
        }

        guard let urlString = zipAsset?["browser_download_url"] as? String,
              let assetURL = URL(string: urlString) else {
            state = .idle
            return
        }

        downloadURL = assetURL
        state = .available(version: remoteVersion, notes: notes)
    }

    func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    // MARK: - Download & install

    func downloadAndInstall() {
        #if DEBUG
        if downloadURL == nil {
            simulateDownloading()
            return
        }
        #endif
        guard let url = downloadURL else { return }
        state = .downloading(progress: 0)

        let delegate = UpdateDownloadDelegate(
            onProgress: { [weak self] progress in
                DispatchQueue.main.async {
                    self?.state = .downloading(progress: min(progress, 1.0))
                }
            },
            onFinished: { [weak self] tempURL in
                DispatchQueue.main.async {
                    self?.extractAndInstall(zipURL: tempURL)
                }
            },
            onError: { [weak self] message in
                DispatchQueue.main.async {
                    self?.state = .failed(message)
                }
            }
        )
        downloadDelegate = delegate

        let config = URLSessionConfiguration.default
        downloadSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        downloadTask = downloadSession?.downloadTask(with: url)
        downloadTask?.resume()
    }

    func dismiss() {
        if case .available(let version, _) = state {
            dismissedVersion = version
        }
        downloadTask?.cancel()
        downloadTask = nil
        downloadDelegate = nil
        state = .idle
    }

    // MARK: - Extract & relaunch

    private func extractAndInstall(zipURL: URL) {
        state = .installing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let extractDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("DemolishUpdate_\(UUID().uuidString)")

            do {
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-xk", zipURL.path, extractDir.path]
                ditto.standardOutput = FileHandle.nullDevice
                ditto.standardError = FileHandle.nullDevice
                try ditto.run()
                ditto.waitUntilExit()

                guard ditto.terminationStatus == 0 else {
                    DispatchQueue.main.async { self?.state = .failed("Failed to extract update") }
                    return
                }

                let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
                guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                    DispatchQueue.main.async { self?.state = .failed("No app found in update archive") }
                    return
                }

                try? FileManager.default.removeItem(at: zipURL)

                DispatchQueue.main.async {
                    self?.launchUpdaterAndQuit(newAppURL: newApp)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.state = .failed("Update failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func launchUpdaterAndQuit(newAppURL: URL) {
        let currentAppPath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        sleep 0.5
        rm -rf "\(currentAppPath)"
        cp -R "\(newAppURL.path)" "\(currentAppPath)"
        xattr -dr com.apple.quarantine "\(currentAppPath)" 2>/dev/null || true
        open "\(currentAppPath)"
        rm -rf "\(newAppURL.deletingLastPathComponent().path)"
        rm -f "$0"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("demolish_updater_\(UUID().uuidString).sh")

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            state = .failed("Failed to launch updater: \(error.localizedDescription)")
        }
    }
}

// MARK: - Download delegate (non-MainActor)

nonisolated final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let onFinished: @Sendable (URL) -> Void
    private let onError: @Sendable (String) -> Void

    init(
        onProgress: @escaping @Sendable (Double) -> Void,
        onFinished: @escaping @Sendable (URL) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.onProgress = onProgress
        self.onFinished = onFinished
        self.onError = onError
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        onProgress(progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("DemolishUpdate.zip")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: location, to: dest)
            onFinished(dest)
        } catch {
            onError("Failed to save download")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error, (error as NSError).code != NSURLErrorCancelled else { return }
        onError("Download failed: \(error.localizedDescription)")
    }
}

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
        UpdateLogger.shared.info("startChecking() called (currentVersion=\(currentVersion), bundlePath=\(Bundle.main.bundlePath))")
        #if DEBUG
        if ProcessInfo.processInfo.environment["SIMULATE_UPDATE"] == "1" {
            UpdateLogger.shared.info("SIMULATE_UPDATE=1 — scheduling fake update")
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
        UpdateLogger.shared.info("stopChecking()")
        checkTimer?.invalidate()
        checkTimer = nil
    }

    func revealLogInFinder() {
        let url = UpdateLogger.logFileURL
        UpdateLogger.shared.info("revealLogInFinder() -> \(url.path)")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
            UpdateLogger.shared.info("checkForUpdate() skipped — current state is \(state)")
            return
        default:
            break
        }

        state = .checking

        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            UpdateLogger.shared.error("checkForUpdate() — invalid URL: \(urlString)")
            state = .idle
            return
        }

        UpdateLogger.shared.info("checkForUpdate() GET \(urlString)")

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
        if let error = error {
            UpdateLogger.shared.error("check request failed: \(error.localizedDescription)")
            state = .idle
            return
        }
        guard let http = response as? HTTPURLResponse else {
            UpdateLogger.shared.error("check response not HTTPURLResponse")
            state = .idle
            return
        }
        guard http.statusCode == 200, let data = data else {
            UpdateLogger.shared.error("check HTTP \(http.statusCode); bytes=\(data?.count ?? 0)")
            state = .idle
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            UpdateLogger.shared.error("check — failed to parse JSON response (bytes=\(data.count))")
            state = .idle
            return
        }

        let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let notes = (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        UpdateLogger.shared.info("check ok — remoteTag=\(tagName) remoteVersion=\(remoteVersion) currentVersion=\(currentVersion) assets=\(assets.count)")

        guard isNewerVersion(remoteVersion, than: currentVersion) else {
            UpdateLogger.shared.info("no newer version available")
            state = .idle
            return
        }

        if remoteVersion == dismissedVersion {
            UpdateLogger.shared.info("remoteVersion \(remoteVersion) was previously dismissed in this session")
            state = .idle
            return
        }

        let zipAsset = assets.first { asset in
            guard let name = asset["name"] as? String else { return false }
            return name.hasSuffix(".zip")
        }

        guard let urlString = zipAsset?["browser_download_url"] as? String,
              let assetURL = URL(string: urlString) else {
            let names = assets.compactMap { $0["name"] as? String }.joined(separator: ", ")
            UpdateLogger.shared.error("no .zip asset found in release (assets=[\(names)])")
            state = .idle
            return
        }

        UpdateLogger.shared.info("update available v\(remoteVersion) — asset=\(assetURL.absoluteString)")
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
        UpdateLogger.shared.info("downloadAndInstall() invoked (state=\(state), downloadURL=\(downloadURL?.absoluteString ?? "nil"))")
        #if DEBUG
        if downloadURL == nil {
            UpdateLogger.shared.info("no downloadURL in DEBUG — running simulated download")
            simulateDownloading()
            return
        }
        #endif
        guard let url = downloadURL else {
            UpdateLogger.shared.error("downloadAndInstall() aborted — downloadURL is nil")
            state = .failed("No download URL available")
            return
        }
        UpdateLogger.shared.info("starting download from \(url.absoluteString)")
        state = .downloading(progress: 0)

        var lastLoggedPercent = -1
        let delegate = UpdateDownloadDelegate(
            onProgress: { [weak self] progress in
                let percent = Int(progress * 100)
                if percent >= lastLoggedPercent + 10 {
                    lastLoggedPercent = percent
                    UpdateLogger.shared.info("download progress \(percent)%")
                }
                DispatchQueue.main.async {
                    self?.state = .downloading(progress: min(progress, 1.0))
                }
            },
            onFinished: { [weak self] tempURL in
                let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? UInt64) ?? 0
                UpdateLogger.shared.info("download finished — saved to \(tempURL.path) (\(size) bytes)")
                DispatchQueue.main.async {
                    self?.extractAndInstall(zipURL: tempURL)
                }
            },
            onError: { [weak self] message in
                UpdateLogger.shared.error("download error: \(message)")
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
        UpdateLogger.shared.info("dismiss() called (state=\(state))")
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
        UpdateLogger.shared.info("extractAndInstall() — zip=\(zipURL.path)")
        state = .installing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let extractDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("DemolishUpdate_\(UUID().uuidString)")
            UpdateLogger.shared.info("extract dir = \(extractDir.path)")

            do {
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-xk", zipURL.path, extractDir.path]

                let outPipe = Pipe()
                let errPipe = Pipe()
                ditto.standardOutput = outPipe
                ditto.standardError = errPipe

                try ditto.run()
                ditto.waitUntilExit()

                let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                UpdateLogger.shared.info("ditto exit=\(ditto.terminationStatus)")
                if !outStr.isEmpty { UpdateLogger.shared.info("ditto stdout: \(outStr.trimmingCharacters(in: .whitespacesAndNewlines))") }
                if !errStr.isEmpty { UpdateLogger.shared.warn("ditto stderr: \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))") }

                guard ditto.terminationStatus == 0 else {
                    let detail = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let msg = detail.isEmpty
                        ? "Failed to extract update (ditto exit \(ditto.terminationStatus))"
                        : "Failed to extract update: \(detail)"
                    DispatchQueue.main.async { self?.state = .failed(msg) }
                    return
                }

                let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
                let names = contents.map { $0.lastPathComponent }.joined(separator: ", ")
                UpdateLogger.shared.info("extract contents: [\(names)]")

                guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                    UpdateLogger.shared.error("no .app bundle found after extract")
                    DispatchQueue.main.async { self?.state = .failed("No app found in update archive") }
                    return
                }
                UpdateLogger.shared.info("found new app at \(newApp.path)")

                try? FileManager.default.removeItem(at: zipURL)

                DispatchQueue.main.async {
                    self?.launchUpdaterAndQuit(newAppURL: newApp)
                }
            } catch {
                UpdateLogger.shared.error("extractAndInstall threw: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.state = .failed("Update failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func launchUpdaterAndQuit(newAppURL: URL) {
        let currentAppPath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let updaterLogPath = UpdateLogger.updaterScriptLogFileURL.path
        let updaterLogDir = UpdateLogger.logsDirectory().path

        UpdateLogger.shared.info("launchUpdaterAndQuit pid=\(pid) current=\(currentAppPath) new=\(newAppURL.path) updaterLog=\(updaterLogPath)")

        let script = """
        #!/bin/bash
        LOG_DIR=\(shellQuote(updaterLogDir))
        LOG=\(shellQuote(updaterLogPath))
        mkdir -p "$LOG_DIR"
        exec >>"$LOG" 2>&1
        echo "=============================="
        echo "Updater started $(date '+%Y-%m-%d %H:%M:%S')"
        echo "pid of parent: \(pid)"
        echo "current app:   \(currentAppPath)"
        echo "new app:       \(newAppURL.path)"
        set -x

        # Wait for the parent app to exit (max ~30s).
        i=0
        while kill -0 \(pid) 2>/dev/null; do
          sleep 0.2
          i=$((i+1))
          if [ "$i" -gt 150 ]; then
            echo "parent still alive after 30s — continuing anyway"
            break
          fi
        done
        sleep 0.5

        rm -rf \(shellQuote(currentAppPath))
        rm_status=$?
        echo "rm exited with $rm_status"

        cp -R \(shellQuote(newAppURL.path)) \(shellQuote(currentAppPath))
        cp_status=$?
        echo "cp exited with $cp_status"

        if [ "$cp_status" -ne 0 ]; then
          echo "FATAL: cp failed; aborting before open"
          exit $cp_status
        fi

        xattr -dr com.apple.quarantine \(shellQuote(currentAppPath)) 2>/dev/null || true

        open \(shellQuote(currentAppPath))
        open_status=$?
        echo "open exited with $open_status"

        rm -rf \(shellQuote(newAppURL.deletingLastPathComponent().path))
        echo "Updater finished $(date '+%Y-%m-%d %H:%M:%S')"
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
            UpdateLogger.shared.info("wrote updater script to \(scriptURL.path)")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            UpdateLogger.shared.info("updater script launched (pid=\(process.processIdentifier)); quitting app in 0.3s")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            UpdateLogger.shared.error("failed to launch updater: \(error.localizedDescription)")
            state = .failed("Failed to launch updater: \(error.localizedDescription)")
        }
    }

    private func shellQuote(_ s: String) -> String {
        // Wrap in single quotes and escape any embedded single quotes.
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
        if let http = downloadTask.response as? HTTPURLResponse {
            UpdateLogger.shared.info("download HTTP \(http.statusCode) from \(http.url?.absoluteString ?? "?") (expected=\(downloadTask.countOfBytesExpectedToReceive), received=\(downloadTask.countOfBytesReceived))")
            guard (200..<300).contains(http.statusCode) else {
                onError("Download failed: HTTP \(http.statusCode)")
                return
            }
        }

        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("DemolishUpdate.zip")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: location, to: dest)
            onFinished(dest)
        } catch {
            UpdateLogger.shared.error("copy from \(location.path) to \(dest.path) failed: \(error.localizedDescription)")
            onError("Failed to save download: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error, (error as NSError).code != NSURLErrorCancelled else { return }
        UpdateLogger.shared.error("URLSessionTask didCompleteWithError: \(error.localizedDescription)")
        onError("Download failed: \(error.localizedDescription)")
    }
}

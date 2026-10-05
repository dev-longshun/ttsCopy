//
//  UpdaterController.swift
//  ttsCopy
//
//  应用内更新：轮询 GitHub Releases → 下载 DMG → 校验签名 → 替换 .app → 重启
//  发布端见 .github/workflows/build-dmg.yml（Developer ID 签名 + 公证）
//

import AppKit
import Combine
import CryptoKit
import Foundation
import UserNotifications

// MARK: - GitHub API 模型（放在文件级，避免被 MainActor 隔离）

private struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft, prerelease, assets
    }
}

private struct GitHubAsset: Decodable, Sendable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

struct RemoteUpdateAsset: Sendable {
    let name: String
    let version: String
    let downloadURL: URL
    let sha256: String?
}

// MARK: - Updater

@MainActor
final class UpdaterController: ObservableObject {

    // MARK: 配置

    /// CI 发布 DMG 的仓库，与 build-dmg.yml 所在仓库一致
    nonisolated static let githubOwner = "dev-longshun"
    nonisolated static let githubRepo = "ttsCopy"
    /// 只接受这个 Team 的 Developer ID 签名包
    nonisolated static let teamIdentifier = "YV73GGQ26P"
    /// DMG 命名：ttsCopy-<版本>.dmg
    nonisolated static let assetPrefix = "ttsCopy-"

    nonisolated private static let autoCheckKey = "autoCheckForUpdates"
    nonisolated private static let notifiedVersionKey = "updateNotifiedVersion"

    /// 后台检查间隔
    nonisolated private static let periodicCheckInterval: TimeInterval = 30 * 60
    /// 打开面板补查的最小间隔，避免频繁开关面板刷 GitHub API
    nonisolated private static let panelOpenCheckMinInterval: TimeInterval = 10 * 60

    // MARK: UI 状态

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case installing
        /// 新版已就绪、替换脚本在等本进程退出，但退出被取消了
        case readyToInstall
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var availableVersion: String?
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var canCheckForUpdates = true

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyChecksForUpdates, forKey: Self.autoCheckKey)
        }
    }

    private var availableAsset: RemoteUpdateAsset?
    private var checkTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var autoCheckScheduled = false
    private var periodicTimer: Timer?
    private var lastCheckStartedAt: Date?
    /// 替换脚本已启动并在等待退出：禁止再次检查 / 安装，避免两个脚本抢着替换
    private var replaceHelperLaunched = false

    // MARK: Init

    init() {
        if UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.autoCheckKey)
        }
        automaticallyChecksForUpdates = UserDefaults.standard.bool(forKey: Self.autoCheckKey)
    }

    // MARK: 生命周期

    /// 启动后调用一次：4 秒后检查一次，之后每 30 分钟检查一次
    func startDeferred() {
        #if DEBUG
        // Xcode 调试版不做后台检查，避免开发时反复提示
        return
        #else
        guard !autoCheckScheduled else { return }
        autoCheckScheduled = true
        lastCheckStartedAt = Date()

        periodicTimer = Timer.scheduledTimer(
            withTimeInterval: Self.periodicCheckInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.backgroundCheck() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.backgroundCheck()
        }
        #endif
    }

    /// 菜单栏面板打开时调用：距上次检查超过 10 分钟就补查
    func panelDidOpen() {
        #if !DEBUG
        if let last = lastCheckStartedAt,
           Date().timeIntervalSince(last) < Self.panelOpenCheckMinInterval {
            return
        }
        backgroundCheck()
        #endif
    }

    private func backgroundCheck() {
        guard automaticallyChecksForUpdates else { return }
        checkForUpdates(userInitiated: false)
    }

    /// 菜单栏图标红点 / 面板更新横幅是否显示
    var showsUpdateBadge: Bool {
        Self.badgeVisible(phase: phase, availableVersion: availableVersion)
    }

    nonisolated static func badgeVisible(phase: Phase, availableVersion: String?) -> Bool {
        switch phase {
        case .available, .downloading, .installing, .readyToInstall:
            return true
        case .failed:
            // 安装失败但新版还在，可以重试
            return availableVersion != nil
        case .idle, .checking, .upToDate:
            return false
        }
    }

    // MARK: 对外操作

    func checkForUpdates() {
        checkForUpdates(userInitiated: true)
    }

    /// 一键更新：下载 → 校验 → 替换 → 重启
    func installAndRelaunch() {
        guard installTask == nil, !replaceHelperLaunched else { return }
        #if DEBUG
        phase = .failed
        statusMessage = "调试版不支持应用内更新，请在「应用程序」里的正式版中更新"
        return
        #else
        installTask = Task { [weak self] in
            guard let self else { return }
            defer { self.installTask = nil }
            do {
                if self.availableAsset == nil {
                    try await self.performCheck(userInitiated: true)
                }
                guard let asset = self.availableAsset else { return }
                try await self.performInstall(asset: asset)
            } catch is CancellationError {
                // 忽略
            } catch {
                self.phase = .failed
                self.statusMessage = error.localizedDescription
                self.canCheckForUpdates = true
            }
        }
        #endif
    }

    /// 「退出并安装」：退出被取消后，再次尝试退出让替换脚本继续
    func quitToFinishInstall() {
        guard replaceHelperLaunched, phase == .readyToInstall else { return }
        phase = .installing
        statusMessage = "正在重启…"
        quitForPendingInstall()
    }

    // MARK: 检查

    private func checkForUpdates(userInitiated: Bool) {
        guard checkTask == nil, installTask == nil, !replaceHelperLaunched else { return }
        lastCheckStartedAt = Date()
        checkTask = Task { [weak self] in
            guard let self else { return }
            defer { self.checkTask = nil }
            do {
                try await self.performCheck(userInitiated: userInitiated)
            } catch is CancellationError {
                // 忽略
            } catch {
                // 后台检查失败（如断网）保留上次结果，不打扰
                if userInitiated || self.phase == .checking {
                    self.phase = .failed
                    self.statusMessage = error.localizedDescription
                }
                self.canCheckForUpdates = true
            }
        }
    }

    private func performCheck(userInitiated: Bool) async throws {
        if userInitiated {
            phase = .checking
            statusMessage = "正在检查更新…"
            availableVersion = nil
            availableAsset = nil
            downloadProgress = 0
        }
        canCheckForUpdates = false

        let releases = try await Self.fetchReleases()
        let local = Self.currentVersionString()

        guard let asset = Self.pickAsset(from: releases),
              Self.isRemoteVersion(asset.version, newerThan: local) else {
            availableVersion = nil
            availableAsset = nil
            phase = .upToDate
            statusMessage = "已是最新版本"
            canCheckForUpdates = true
            return
        }

        availableAsset = asset
        availableVersion = asset.version
        phase = .available
        statusMessage = "发现新版本 v\(asset.version)"
        canCheckForUpdates = true
        notifyNewVersionOnce(asset.version)
    }

    /// 同一个版本只发一次系统通知（菜单栏 App 没有主窗口，靠通知提醒）
    private func notifyNewVersionOnce(_ version: String) {
        guard UserDefaults.standard.string(forKey: Self.notifiedVersionKey) != version else { return }
        UserDefaults.standard.set(version, forKey: Self.notifiedVersionKey)

        let content = UNMutableNotificationContent()
        content.title = "TTS Copy - 有新版本"
        content.body = "v\(version) 已发布，点击菜单栏图标即可更新"
        let request = UNNotificationRequest(
            identifier: "update-\(version)", content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("⚠️ [Updater] 发送更新通知失败: \(error)") }
        }
    }

    // MARK: 安装流程

    private func performInstall(asset: RemoteUpdateAsset) async throws {
        let destApp = Bundle.main.bundleURL
        try Self.ensureReplaceable(destApp)

        phase = .downloading
        statusMessage = "正在下载更新…"
        canCheckForUpdates = false
        downloadProgress = 0

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ttsCopyUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let dmgURL = workDir.appendingPathComponent(asset.name)
        try await Self.download(url: asset.downloadURL, to: dmgURL) { [weak self] fraction in
            Task { @MainActor in
                self?.downloadProgress = fraction
            }
        }

        if let expected = asset.sha256 {
            statusMessage = "正在校验下载文件…"
            let actual = try Self.sha256Hex(of: dmgURL)
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                throw UpdateError.checksumMismatch
            }
        }

        phase = .installing
        statusMessage = "正在安装更新…"
        downloadProgress = 1

        let mountPoint = workDir.appendingPathComponent("mnt", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        try await Self.run("/usr/bin/hdiutil", arguments: [
            "attach", dmgURL.path,
            "-nobrowse",
            "-readonly",
            "-noautoopen",
            "-mountpoint", mountPoint.path,
        ])
        defer {
            try? Self.runSync("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
        }

        guard let sourceApp = Self.findApp(in: mountPoint) else {
            throw UpdateError.appNotFoundInDMG
        }

        // 复制一份到工作目录，DMG 卸载后仍可用
        let stagedApp = workDir.appendingPathComponent("ttsCopy.app")
        try Self.runSync("/usr/bin/ditto", arguments: [sourceApp.path, stagedApp.path])
        try? await Self.run("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])

        // 必须是本 Team 的 Developer ID 签名、且 bundle id 一致，否则拒绝安装
        try await Self.verifySignature(of: stagedApp)

        try Self.writeAndLaunchReplaceHelper(
            stagedApp: stagedApp,
            destApp: destApp,
            workDir: workDir
        )
        replaceHelperLaunched = true

        statusMessage = "正在重启…"
        try await Task.sleep(nanoseconds: 300_000_000)
        quitForPendingInstall()
    }

    /// 退出让替换脚本接手。NSApp.terminate 成功时不会返回；返回了说明退出被取消
    private func quitForPendingInstall() {
        NSApp.terminate(nil)
        phase = .readyToInstall
        statusMessage = "新版本已就绪，退出 TTS Copy 即可完成安装"
        canCheckForUpdates = false
    }

    // MARK: 网络

    nonisolated private static func fetchReleases() async throws -> [GitHubRelease] {
        let url = URL(string:
            "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases?per_page=10"
        )!
        var request = URLRequest(url: url)
        request.setValue("ttsCopy/\(currentVersionString())", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw UpdateError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    nonisolated private static func download(
        url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let delegate = DownloadDelegate(destination: destination, onProgress: onProgress, continuation: cont)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            // 下载期间持有 delegate
            delegate.session = session
            session.downloadTask(with: url).resume()
        }
    }

    // MARK: 版本

    nonisolated static func currentVersionString() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// 取最新的正式 Release（跳过草稿 / 预发布）里的 ttsCopy-*.dmg
    nonisolated private static func pickAsset(from releases: [GitHubRelease]) -> RemoteUpdateAsset? {
        for rel in releases where !rel.draft && !rel.prerelease {
            guard let asset = rel.assets.first(where: {
                $0.name.hasPrefix(assetPrefix) && $0.name.hasSuffix(".dmg")
            }) else { continue }

            var version = String(asset.name.dropFirst(assetPrefix.count).dropLast(".dmg".count))
            if version.isEmpty {
                version = rel.tagName.hasPrefix("v") ? String(rel.tagName.dropFirst()) : rel.tagName
            }
            let sha = asset.digest.flatMap { digest -> String? in
                let prefix = "sha256:"
                guard digest.lowercased().hasPrefix(prefix) else { return nil }
                return String(digest.dropFirst(prefix.count))
            }
            return RemoteUpdateAsset(
                name: asset.name,
                version: version,
                downloadURL: asset.browserDownloadURL,
                sha256: sha
            )
        }
        return nil
    }

    /// 逐段比较数字版本：1.0.4.12 > 1.0.4（缺的段按 0 算）
    nonisolated static func isRemoteVersion(_ remote: String, newerThan local: String) -> Bool {
        let r = versionNumbers(remote)
        let l = versionNumbers(local)
        guard !r.isEmpty else { return false }
        guard !l.isEmpty else { return true }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    nonisolated private static func versionNumbers(_ raw: String) -> [Int] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") { s = String(s.dropFirst()) }
        return s.split(separator: ".").compactMap { Int($0) }
    }

    // MARK: 文件 / 签名

    /// 替换前检查：不能在 App Translocation 只读路径里运行，目标目录要可写
    nonisolated private static func ensureReplaceable(_ appURL: URL) throws {
        if appURL.path.contains("/AppTranslocation/") {
            throw UpdateError.translocated
        }
        let parent = appURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else {
            throw UpdateError.notWritable(parent)
        }
    }

    nonisolated private static func findApp(in mountPoint: URL) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        if let direct = items.first(where: { $0.lastPathComponent == "ttsCopy.app" }) {
            return direct
        }
        return items.first(where: { $0.pathExtension == "app" })
    }

    /// 校验：Developer ID 证书链 + Team ID + bundle id 都对得上
    nonisolated private static func verifySignature(of app: URL) async throws {
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.longshun.ttscopy"
        let requirement = """
        =identifier "\(bundleID)" and anchor apple generic \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
        and certificate leaf[subject.OU] = "\(teamIdentifier)"
        """
        do {
            try await run("/usr/bin/codesign", arguments: [
                "--verify", "--deep", "--strict", "-R", requirement, app.path,
            ])
        } catch {
            throw UpdateError.signatureInvalid
        }
    }

    nonisolated private static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 启动独立 shell 脚本：等本进程退出 → 同卷 rename 替换 .app → 重新打开
    ///
    /// 进程还在时绝不动 bundle（按 PID + 启动时间等待，防 PID 复用）。
    /// 新包先复制到目标旁边，退出后只剩两次同卷 mv，关机时退出也不会留下半个 app。
    nonisolated private static func writeAndLaunchReplaceHelper(
        stagedApp: URL,
        destApp: URL,
        workDir: URL
    ) throws {
        let scriptURL = workDir.appendingPathComponent("replace.sh")
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        set -euo pipefail
        SRC=\(shellQuote(stagedApp.path))
        DEST=\(shellQuote(destApp.path))
        WORK=\(shellQuote(workDir.path))
        TARGET_PID=\(ourPID)
        LOG="$WORK/replace.log"
        exec >>"$LOG" 2>&1
        echo "ttsCopy replace helper pid=$$ waiting for $TARGET_PID"
        TARGET_START="$(ps -p "$TARGET_PID" -o lstart= 2>/dev/null || true)"
        if [ ! -d "$SRC" ]; then
          echo "staged app missing: $SRC"
          exit 1
        fi
        # 不带 .app 后缀，避免 Launch Services 注册这份临时副本
        STAGING="$(dirname "$DEST")/.ttsCopy-update-staging"
        rm -rf "$STAGING"
        /usr/bin/ditto "$SRC" "$STAGING"
        echo "staged at $STAGING"
        while [ -n "$TARGET_START" ] && \\
          [ "$(ps -p "$TARGET_PID" -o lstart= 2>/dev/null || true)" = "$TARGET_START" ]; do
          sleep 0.5
        done
        echo "ttsCopy exited, swapping"
        sleep 0.5
        BACKUP="${DEST}.update-backup"
        rm -rf "$BACKUP"
        if [ -d "$DEST" ]; then
          mv "$DEST" "$BACKUP"
        fi
        if ! mv "$STAGING" "$DEST"; then
          echo "swap failed, restoring previous app"
          if [ -d "$BACKUP" ]; then mv "$BACKUP" "$DEST"; fi
          exit 1
        fi
        rm -rf "$BACKUP"
        /usr/bin/open "$DEST"
        ( sleep 8; rm -rf "$WORK" ) &
        echo "done"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .userInitiated
        try process.run()
    }

    nonisolated private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    nonisolated private static func run(
        _ launchPath: String,
        arguments: [String]
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try runSync(launchPath, arguments: arguments)
        }.value
    }

    @discardableResult
    nonisolated private static func runSync(
        _ launchPath: String,
        arguments: [String]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw UpdateError.commandFailed(
                launchPath,
                process.terminationStatus,
                stderr.isEmpty ? stdout : stderr
            )
        }
        return stdout
    }
}

// MARK: - 下载代理

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let onProgress: @Sendable (Double) -> Void
    let continuation: CheckedContinuation<Void, Error>
    var session: URLSession?
    private var finished = false

    init(
        destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void,
        continuation: CheckedContinuation<Void, Error>
    ) {
        self.destination = destination
        self.onProgress = onProgress
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                finish(.failure(UpdateError.httpStatus(http.statusCode)))
                return
            }
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
            onProgress(1)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        session?.finishTasksAndInvalidate()
        session = nil
    }
}

// MARK: - 错误

enum UpdateError: LocalizedError {
    case httpStatus(Int)
    case checksumMismatch
    case appNotFoundInDMG
    case signatureInvalid
    case translocated
    case notWritable(String)
    case commandFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "GitHub 返回 HTTP \(code)"
        case .checksumMismatch:
            return "下载文件校验失败，请重试"
        case .appNotFoundInDMG:
            return "下载的 DMG 里没有找到 ttsCopy.app"
        case .signatureInvalid:
            return "新版本签名校验未通过，已取消安装"
        case .translocated:
            return "请先把 TTS Copy 拖到「应用程序」文件夹再更新"
        case .notWritable(let path):
            return "没有写入权限：\(path)"
        case .commandFailed(let cmd, let status, let detail):
            let snippet = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (cmd as NSString).lastPathComponent
            return snippet.isEmpty
                ? "\(name) 执行失败（退出码 \(status)）"
                : "\(name) 执行失败（退出码 \(status)）：\(snippet)"
        }
    }
}

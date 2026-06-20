import Foundation
import SystemConfiguration

// MARK: - Proxy settings (UserDefaults-backed)

struct ProxySettings {
    private static let hostKey  = "CodexGauge_proxyHost"
    private static let portKey  = "CodexGauge_proxyPort"
    private static let useSystemProxyKey = "CodexGauge_useSystemProxy"

    static var useSystemProxy: Bool {
        get { UserDefaults.standard.object(forKey: useSystemProxyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: useSystemProxyKey) }
    }

    static var manualHost: String {
        get { UserDefaults.standard.string(forKey: hostKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: hostKey) }
    }

    static var manualPort: String {
        get { UserDefaults.standard.string(forKey: portKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: portKey) }
    }

    /// Read macOS system proxy settings (System Preferences → Network → Proxies)
    static func systemProxy() -> (host: String, port: String)? {
        guard let store = SCDynamicStoreCreate(nil, "CodexGauge" as CFString, nil, nil) else {
            return nil
        }
        guard let proxies = SCDynamicStoreCopyProxies(store) as? [String: Any] else {
            return nil
        }

        // Try HTTPS proxy first
        if (proxies["HTTPSEnable"] as? Int) == 1,
           let host = proxies["HTTPSProxy"] as? String, !host.isEmpty,
           let port = proxies["HTTPSPort"] as? Int, port > 0 {
            return (host, String(port))
        }
        // Fall back to HTTP proxy
        if (proxies["HTTPEnable"] as? Int) == 1,
           let host = proxies["HTTPProxy"] as? String, !host.isEmpty,
           let port = proxies["HTTPPort"] as? Int, port > 0 {
            return (host, String(port))
        }
        return nil
    }

    /// Resolve the effective proxy: manual override > system proxy > none
    static func effective() -> (host: String, port: String)? {
        if !useSystemProxy, !manualHost.isEmpty, !manualPort.isEmpty {
            return (manualHost, manualPort)
        }
        if useSystemProxy, let sys = systemProxy() {
            return sys
        }
        return nil
    }
}

// MARK: - Quota Fetcher

enum QuotaFetcher {

    static func fetch() async throws -> QuotaData {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try fetchSync()
                    continuation.resume(returning: data)
                } catch {
                    print("[QuotaFetcher] Error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Locate codex_fetch.py — Bundle resource only (no hardcoded dev path)
    private static func locateScript() throws -> URL {
        if let path = Bundle.main.path(forResource: "codex_fetch", ofType: "py") {
            return URL(fileURLWithPath: path)
        }
        throw QuotaError.scriptNotFound
    }

    private static func fetchSync() throws -> QuotaData {
        let logURL = URL(fileURLWithPath: "/tmp/codex_gauge_debug.log")
        var logLines: [String] = []
        func log(_ msg: String) {
            let line = "[\(Date())] \(msg)"
            logLines.append(line)
            print("[QuotaFetcher] \(msg)")
        }

        let scriptURL = try locateScript()
        let resultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex_result_\(UUID().uuidString).json")

        log("=== start ===")
        log("script: \(scriptURL.path)")

        defer { try? FileManager.default.removeItem(at: resultURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path, resultURL.path]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory

        var env = ProcessInfo.processInfo.environment
        env["PYTHONIOENCODING"] = "utf-8"

        // Inject proxy settings for Python script
        if let proxy = ProxySettings.effective() {
            env["CODEX_PROXY_HOST"] = proxy.host
            env["CODEX_PROXY_PORT"] = proxy.port
            log("proxy: \(proxy.host):\(proxy.port) (system=\(ProxySettings.useSystemProxy))")
        } else {
            log("proxy: none (no system proxy detected)")
        }
        process.environment = env

        // stderr pipe for debug output
        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        log("launching Python...")
        do {
            try process.run()
            log("PID: \(process.processIdentifier)")
        } catch {
            log("launch failed: \(error)")
            try? logLines.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
            throw error
        }

        // Wait for result file (25 s timeout)
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: resultURL.path) {
                Thread.sleep(forTimeInterval: 0.3)
                log("result file ready")
                break
            }
            if !process.isRunning {
                Thread.sleep(forTimeInterval: 0.3)
                log("process exited status=\(process.terminationStatus)")
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if let errText = String(data: errData, encoding: .utf8), !errText.isEmpty {
            log("Python stderr:\(errText)")
        }

        process.waitUntilExit()

        // Write debug log
        try? logLines.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)

        guard FileManager.default.fileExists(atPath: resultURL.path) else {
            throw QuotaError.noResultFile
        }

        let rawData = try Data(contentsOf: resultURL)
        let rawStr = String(data: rawData, encoding: .utf8) ?? "?"
        log("result: \(rawStr)")

        guard let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
            throw QuotaError.invalidResponse(rawStr)
        }

        guard json["ok"] as? Bool == true else {
            let err = json["error"] as? String ?? "unknown"
            throw QuotaError.codexError(err)
        }

        let data = QuotaData(
            remainingPercent: json["remainingPercent"] as? Int ?? 0,
            usedPercent: json["usedPercent"] as? Int ?? 0,
            planType: json["planType"] as? String ?? "unknown",
            resetsAt: (json["resetsAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) },
            fetchedAt: Date(),
            primaryRemaining: json["primaryRemaining"] as? Int,
            secondaryRemaining: json["secondaryRemaining"] as? Int
        )
        log("OK \(data.remainingPercent)% remaining")
        QuotaStore.save(data)
        return data
    }
}

enum QuotaError: LocalizedError {
    case scriptNotFound
    case noResultFile
    case invalidResponse(String)
    case codexError(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:           return "codex_fetch.py not found in app bundle"
        case .noResultFile:             return "No data received"
        case .invalidResponse(let m):   return "Invalid response: \(m)"
        case .codexError(let m):        return m
        }
    }
}

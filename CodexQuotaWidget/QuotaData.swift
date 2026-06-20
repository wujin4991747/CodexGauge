import Foundation

/// Quota data model
struct QuotaData: Codable {
    let remainingPercent: Int
    let usedPercent: Int
    let planType: String
    let resetsAt: Date?
    let fetchedAt: Date
    let primaryRemaining: Int?
    let secondaryRemaining: Int?

    var state: QuotaState {
        if remainingPercent <= 0 { return .critical }
        if remainingPercent < 10 { return .warning }
        return .ok
    }
}

enum QuotaState: String, Codable {
    case ok, warning, critical
}

// MARK: - Shared file storage

enum QuotaStore {
    private static let fileName = "quota.json"

    static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CodexGauge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func save(_ data: QuotaData) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }

    static func load() -> QuotaData? {
        guard let raw = try? Data(contentsOf: fileURL),
              let data = try? JSONDecoder().decode(QuotaData.self, from: raw) else {
            return nil
        }
        return data
    }
}

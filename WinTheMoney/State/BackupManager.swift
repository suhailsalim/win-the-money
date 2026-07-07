import Foundation

/// Automatic backups. Always writes a JSON backup to the app's Documents folder
/// (exposed in the Files app via UIFileSharingEnabled and included in the device's
/// iCloud device-backup). When the iCloud Drive ubiquity container is available
/// (iCloud entitlement + signed-in user), it ALSO writes there so device migration
/// is automatic. Falls back gracefully on the free dev team (no iCloud entitlement).
enum BackupManager {
    static let filename = "WinTheMoney-backup.json"
    private static let lastKey = "wtm_last_backup"

    static var localURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    static func iCloudURL() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let docs = container.appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs.appendingPathComponent(filename)
    }

    static var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil && iCloudURL() != nil
    }

    static var lastBackup: Date? { UserDefaults.standard.object(forKey: lastKey) as? Date }

    /// Writes the backup; returns a human label of where it landed.
    @discardableResult
    static func write(_ data: Data) -> String {
        var locations: [String] = []
        if (try? data.write(to: localURL, options: .atomic)) != nil { locations.append("Files") }
        if let url = iCloudURL(), (try? data.write(to: url, options: .atomic)) != nil { locations.append("iCloud Drive") }
        if !locations.isEmpty { UserDefaults.standard.set(Date(), forKey: lastKey) }
        return locations.isEmpty ? "—" : locations.joined(separator: " + ")
    }

    /// Reads the most recent backup (prefers iCloud, falls back to local Documents).
    static func latestData() -> Data? {
        if let url = iCloudURL() {
            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            if let d = try? Data(contentsOf: url) { return d }
        }
        return try? Data(contentsOf: localURL)
    }

    static var hasBackup: Bool {
        FileManager.default.fileExists(atPath: localURL.path) || (iCloudURL().map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
    }
}

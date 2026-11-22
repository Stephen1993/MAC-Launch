import Foundation

enum DockManager {
    private static let dockDomain = "com.apple.dock" as CFString
    private static let persistentAppsKey = "persistent-apps" as CFString

    static func add(_ app: ApplicationItem, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = addSynchronously(app)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    private static func addSynchronously(_ app: ApplicationItem) -> Bool {
        guard !contains(app) else { return true }

        let urlString = app.url.absoluteString.hasSuffix("/")
            ? app.url.absoluteString
            : app.url.absoluteString + "/"
        var tileData: [String: Any] = [
            "file-data": [
                "_CFURLString": urlString,
                "_CFURLStringType": 15
            ],
            "file-label": app.name
        ]
        if let bundleIdentifier = app.bundleIdentifier {
            tileData["bundle-identifier"] = bundleIdentifier
        }
        let item: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": tileData
        ]

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: item,
            format: .xml,
            options: 0
        ), let xml = String(data: data, encoding: .utf8) else {
            return false
        }

        let defaults = Process()
        defaults.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        defaults.arguments = [
            "write",
            "com.apple.dock",
            "persistent-apps",
            "-array-add",
            xml
        ]

        do {
            try defaults.run()
            defaults.waitUntilExit()
        } catch {
            return false
        }
        guard defaults.terminationStatus == 0 else { return false }

        restartDock()
        return true
    }

    private static func contains(_ app: ApplicationItem) -> Bool {
        guard let items = CFPreferencesCopyAppValue(
            persistentAppsKey,
            dockDomain
        ) as? [[String: Any]] else {
            return false
        }

        let appPath = app.url.standardizedFileURL.path
        return items.contains { item in
            guard
                let tileData = item["tile-data"] as? [String: Any],
                let fileData = tileData["file-data"] as? [String: Any],
                let urlString = fileData["_CFURLString"] as? String,
                let url = URL(string: urlString)
            else { return false }
            return url.standardizedFileURL.path == appPath
        }
    }

    private static func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {}
    }
}

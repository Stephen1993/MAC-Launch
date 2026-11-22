import AppKit
import Combine
import Foundation

struct ApplicationItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage
    let addedAt: Date

    static func == (lhs: ApplicationItem, rhs: ApplicationItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum DropInsertion: Equatable {
    case before(String)
    case after(String)
    case end
}

final class AppModel: ObservableObject {
    @Published var apps: [ApplicationItem] = []
    @Published var query = ""
    @Published var draggedAppID: String?
    @Published var dropInsertion: DropInsertion?

    var onDismiss: (() -> Void)?
    var onDockUpdateBegan: (() -> Void)?
    var onDockUpdateEnded: (() -> Void)?

    private var runningBundleIdentifiers: Set<String> = []
    private let appOrderKey = "customAppOrder.v1"

    func isRunning(_ app: ApplicationItem) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier else { return false }
        return runningBundleIdentifiers.contains(bundleIdentifier)
    }

    func reloadApps() {
        runningBundleIdentifiers = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )

        let discovered = AppCatalog.scan().sorted {
            if $0.addedAt == $1.addedAt {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.addedAt > $1.addedAt
        }
        apps = reconcileOrder(discovered)
    }

    func beginDragging(_ app: ApplicationItem) {
        draggedAppID = app.id
        dropInsertion = nil
        DragAutoScroller.shared.start { [weak self] in
            self?.cancelDragging()
        }
    }

    func setDropTarget(_ app: ApplicationItem) {
        guard
            let draggedAppID,
            let sourceIndex = apps.firstIndex(where: { $0.id == draggedAppID }),
            let targetIndex = apps.firstIndex(where: { $0.id == app.id })
        else {
            dropInsertion = nil
            return
        }

        dropInsertion = sourceIndex < targetIndex
            ? .after(app.id)
            : .before(app.id)
    }

    func setDropAtEnd() {
        guard draggedAppID != nil else {
            dropInsertion = nil
            return
        }
        dropInsertion = .end
    }

    func clearDropTarget(_ app: ApplicationItem) {
        switch dropInsertion {
        case .before(let id), .after(let id):
            if id == app.id {
                dropInsertion = nil
            }
        default:
            break
        }
    }

    func clearEndDropTarget() {
        if dropInsertion == .end {
            dropInsertion = nil
        }
    }

    func finishDragging() {
        guard
            let draggedAppID,
            let sourceIndex = apps.firstIndex(where: { $0.id == draggedAppID }),
            let insertion = dropInsertion
        else {
            cancelDragging()
            DragAutoScroller.shared.stop()
            return
        }

        let previousOrder = apps.map(\.id)
        let movedApp = apps.remove(at: sourceIndex)
        switch insertion {
        case .before(let id):
            if let targetIndex = apps.firstIndex(where: { $0.id == id }) {
                apps.insert(movedApp, at: targetIndex)
            } else {
                apps.append(movedApp)
            }
        case .after(let id):
            if let targetIndex = apps.firstIndex(where: { $0.id == id }) {
                apps.insert(movedApp, at: min(targetIndex + 1, apps.count))
            } else {
                apps.append(movedApp)
            }
        case .end:
            apps.append(movedApp)
        }

        if apps.map(\.id) != previousOrder {
            saveOrder(apps)
        }
        cancelDragging()
        DragAutoScroller.shared.stop()
    }

    func launch(_ app: ApplicationItem) {
        if let running = runningApplication(for: app) {
            if running.activate(options: [.activateAllWindows]) {
                onDismiss?()
            } else {
                showError(
                    title: "无法打开 \(app.name)",
                    message: "未能激活正在运行的应用，请稍后重试。"
                )
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: app.url,
            configuration: configuration
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.showError(
                        title: "无法打开 \(app.name)",
                        message: error.localizedDescription
                    )
                } else {
                    self.onDismiss?()
                }
            }
        }
    }

    func keepInDock(_ app: ApplicationItem) {
        onDockUpdateBegan?()
        let success = DockManager.add(app)
        onDockUpdateEnded?()

        if success {
            return
        }

        showError(
            title: "无法保留 \(app.name)",
            message: "未能修改程序坞设置，请稍后重试。"
        )
    }

    func revealInFinder(_ app: ApplicationItem) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    private func reconcileOrder(_ sortedByDate: [ApplicationItem]) -> [ApplicationItem] {
        guard let savedOrder = UserDefaults.standard.stringArray(forKey: appOrderKey),
              !savedOrder.isEmpty else {
            saveOrder(sortedByDate)
            return sortedByDate
        }

        var positions: [String: Int] = [:]
        var legacyPositions: [String: Int] = [:]
        for (index, key) in savedOrder.enumerated() {
            if key.hasPrefix("/") {
                if positions[key] == nil {
                    positions[key] = index
                }
            } else if legacyPositions[key] == nil {
                legacyPositions[key] = index
            }
        }

        func savedPosition(for app: ApplicationItem) -> Int? {
            if let position = positions[app.id] {
                return position
            }
            guard let bundleIdentifier = app.bundleIdentifier else { return nil }
            return legacyPositions[bundleIdentifier]
        }

        let newApps = sortedByDate.filter { savedPosition(for: $0) == nil }
        let savedApps = sortedByDate
            .filter { savedPosition(for: $0) != nil }
            .sorted { savedPosition(for: $0)! < savedPosition(for: $1)! }
        let orderedApps = newApps + savedApps
        saveOrder(orderedApps)
        return orderedApps
    }

    private func saveOrder(_ orderedApps: [ApplicationItem]) {
        UserDefaults.standard.set(orderedApps.map(\.id), forKey: appOrderKey)
    }

    private func cancelDragging() {
        draggedAppID = nil
        dropInsertion = nil
    }

    private func runningApplication(for app: ApplicationItem) -> NSRunningApplication? {
        guard let bundleIdentifier = app.bundleIdentifier else { return nil }
        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        return runningApps.first {
            $0.bundleURL?.standardizedFileURL.path == app.url.path
        } ?? runningApps.first
    }

    private func showError(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()

        if !NSApp.isActive {
            onDismiss?()
        }
    }
}

enum AppCatalog {
    private static let iconPointSize: CGFloat = 66
    private static let roots: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
    }()

    static func scan() -> [ApplicationItem] {
        let fileManager = FileManager.default
        var urls: [URL] = []
        var visited = Set<String>()

        for root in roots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children where child.pathExtension.lowercased() == "app" {
                let path = child.standardizedFileURL.path
                guard visited.insert(path).inserted else { continue }
                urls.append(child)
            }
        }

        let entries = urls.compactMap { makeEntry(at: $0) }
        let icons = loadIcons(for: entries.map(\.url))

        return entries.enumerated().compactMap { index, entry in
            guard let icon = icons[index] else { return nil }
            return ApplicationItem(
                id: entry.url.path,
                url: entry.url,
                name: entry.name,
                bundleIdentifier: entry.bundleIdentifier,
                icon: icon,
                addedAt: entry.addedAt
            )
        }
    }

    private static func makeEntry(at url: URL) -> ApplicationEntry? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              url.pathExtension.lowercased() == "app" else {
            return nil
        }

        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let name = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent

        return ApplicationEntry(
            url: url.standardizedFileURL,
            name: name,
            bundleIdentifier: bundle?.bundleIdentifier,
            addedAt: addedDate(for: url)
        )
    }

    private static func loadIcons(for urls: [URL]) -> [NSImage?] {
        var icons = Array<NSImage?>(repeating: nil, count: urls.count)
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            autoreleasepool {
                let icon = NSWorkspace.shared.icon(forFile: urls[index].path)
                icon.size = NSSize(width: iconPointSize, height: iconPointSize)
                lock.lock()
                icons[index] = icon
                lock.unlock()
            }
        }

        return icons
    }

    private static func addedDate(for url: URL) -> Date {
        let values = try? url.resourceValues(
            forKeys: [.addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey]
        )
        return values?.addedToDirectoryDate
            ?? values?.creationDate
            ?? values?.contentModificationDate
            ?? .distantPast
    }
}

private struct ApplicationEntry {
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let addedAt: Date
}

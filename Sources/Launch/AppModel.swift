import AppKit
import Combine
import Foundation

struct ApplicationItem: Identifiable {
    let id: String
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage
    let addedAt: Date

    var isSystemApp: Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix("/System/")
    }

    var isLaunchSelf: Bool {
        let selfPath = Bundle.main.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return url.resolvingSymlinksInPath().standardizedFileURL.path == selfPath
    }

    var canUninstall: Bool {
        !isSystemApp && !isLaunchSelf
    }

    var canQuit: Bool {
        !isLaunchSelf && bundleIdentifier != nil
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
        DockManager.add(app) { [weak self] success in
            guard let self else { return }
            self.onDockUpdateEnded?()

            if !success {
                self.showError(
                    title: "无法保留 \(app.name)",
                    message: "未能修改程序坞设置，请稍后重试。"
                )
            }
        }
    }

    func quit(_ app: ApplicationItem) {
        guard app.canQuit, let running = runningApplication(for: app) else { return }
        guard running.terminate() else {
            showError(
                title: "无法退出 \(app.name)",
                message: "应用拒绝了退出请求，请稍后重试。"
            )
            return
        }

        if let bundleIdentifier = app.bundleIdentifier {
            runningBundleIdentifiers.remove(bundleIdentifier)
            objectWillChange.send()
        }
    }

    func revealInFinder(_ app: ApplicationItem) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    func uninstall(_ app: ApplicationItem) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "卸载 \(app.name)？"
        alert.informativeText = "应用会移到废纸篓，仍可从废纸篓恢复。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        NSWorkspace.shared.recycle([app.url]) { [weak self] recycledURLs, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard recycledURLs[app.url] != nil else {
                    self.showError(
                        title: "无法卸载 \(app.name)",
                        message: error?.localizedDescription
                            ?? "未能把应用移到废纸篓，可能没有足够权限。"
                    )
                    return
                }

                self.apps.removeAll { $0.id == app.id }
                self.saveOrder(self.apps)
            }
        }
    }

    private func reconcileOrder(_ sortedByDate: [ApplicationItem]) -> [ApplicationItem] {
        guard let savedOrder = UserDefaults.standard.stringArray(forKey: appOrderKey),
              !savedOrder.isEmpty else {
            saveOrder(sortedByDate)
            return sortedByDate
        }

        var positions: [String: Int] = [:]
        for (index, id) in savedOrder.enumerated() {
            positions[id] = index
        }

        let newApps = sortedByDate.filter { positions[$0.id] == nil }
        let savedApps = sortedByDate
            .filter { positions[$0.id] != nil }
            .sorted { positions[$0.id]! < positions[$1.id]! }
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
        if let exact = runningApps.first(where: {
            $0.bundleURL?.standardizedFileURL.path == app.url.path
        }) {
            return exact
        }
        return runningApps.count == 1 ? runningApps.first : nil
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

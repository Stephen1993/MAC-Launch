import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LauncherView: View {
    @ObservedObject var model: AppModel

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 22, alignment: .top),
        count: 7
    )

    var body: some View {
        let visibleApps = filteredApps

        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                searchHeader(count: visibleApps.count)
                Divider().opacity(0.45)
                appGrid(apps: visibleApps)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
    }

    private var filteredApps: [ApplicationItem] {
        let search = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return model.apps }
        return model.apps.filter { $0.name.localizedStandardContains(search) }
    }

    private func searchHeader(count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.42))

            SearchField(text: $model.query, onSubmit: openFirstMatch)
                .frame(maxWidth: .infinity)

            Text("\(count) 个应用")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.48))
                .fixedSize()
        }
        .padding(.horizontal, 24)
        .frame(height: 58)
    }

    private func appGrid(apps: [ApplicationItem]) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(apps) { app in
                        AppTile(
                            app: app,
                            isRunning: model.isRunning(app),
                            insertionEdge: dropEdge(for: app, in: apps)
                        ) {
                            model.launch(app)
                        } onQuit: {
                            model.quit(app)
                        } onKeepInDock: {
                            model.keepInDock(app)
                        } onReveal: {
                            model.revealInFinder(app)
                        } onUninstall: {
                            model.uninstall(app)
                        }
                        .onDrag {
                            model.beginDragging(app)
                            return NSItemProvider(object: app.id as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: AppTileDropDelegate(model: model, target: app)
                        )
                    }
                }
                Color.clear
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .onDrop(
                        of: [UTType.text],
                        delegate: EndOfGridDropDelegate(model: model)
                    )
            }
            .background(ScrollViewLocator())
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.visible)
        .overlay {
            if apps.isEmpty {
                ContentUnavailableView {
                    Label(
                        model.query.isEmpty ? "还没有应用" : "没有匹配的应用",
                        systemImage: model.query.isEmpty ? "square.grid.3x3" : "magnifyingglass"
                    )
                } description: {
                    Text(model.query.isEmpty ? "请先安装应用" : "试试其他应用名称")
                }
            }
        }
    }

    private func openFirstMatch() {
        guard !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let app = filteredApps.first else { return }
        model.launch(app)
    }

    private func dropEdge(
        for app: ApplicationItem,
        in apps: [ApplicationItem]
    ) -> DropIndicatorEdge? {
        guard let insertion = model.dropInsertion else { return nil }

        switch insertion {
        case .before(let id):
            return id == app.id ? .leading : nil
        case .after(let id):
            return id == app.id ? .trailing : nil
        case .end:
            return apps.last?.id == app.id ? .trailing : nil
        }
    }
}

private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusedSearchField()
        field.placeholderString = "搜索应用"
        field.stringValue = text
        field.font = NSFont.systemFont(ofSize: 17, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        if let cell = field.cell as? NSSearchFieldCell {
            cell.searchButtonCell = nil
            cell.sendsWholeSearchString = true
            cell.sendsSearchStringImmediately = false
        }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField

        init(parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            parent.onSubmit()
            return true
        }
    }
}

private final class FocusedSearchField: NSSearchField {
    private var didRequestFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !didRequestFocus, let window else { return }
        didRequestFocus = true

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}

private struct ScrollViewLocator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        LocatorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class LocatorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }

            DispatchQueue.main.async { [weak self] in
                var ancestor = self?.superview
                while let view = ancestor {
                    if let scrollView = view as? NSScrollView {
                        DragAutoScroller.shared.attach(scrollView)
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
}

private struct AppTile: View {
    let app: ApplicationItem
    let isRunning: Bool
    let insertionEdge: DropIndicatorEdge?
    let onOpen: () -> Void
    let onQuit: () -> Void
    let onKeepInDock: () -> Void
    let onReveal: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 66, height: 66)

                if isRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }
            }

            Text(app.name)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.86))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button("打开", action: onOpen)
            if app.canQuit {
                Button("退出", action: onQuit)
            }
            Button("保留在程序坞", action: onKeepInDock)
            Button("在访达中显示", action: onReveal)
            if app.canUninstall {
                Divider()
                Button("卸载", role: .destructive, action: onUninstall)
            }
        }
        .overlay {
            GeometryReader { proxy in
                if let insertionEdge {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 2.5, height: proxy.size.height - 16)
                        .position(
                            x: insertionEdge == .leading ? -11 : proxy.size.width + 11,
                            y: proxy.size.height / 2
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(.isButton)
    }
}

private struct AppTileDropDelegate: DropDelegate {
    let model: AppModel
    let target: ApplicationItem

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggedAppID = model.draggedAppID else { return false }
        return draggedAppID != target.id
    }

    func dropEntered(info: DropInfo) {
        model.setDropTarget(target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        model.clearDropTarget(target)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.finishDragging()
        return true
    }
}

private struct EndOfGridDropDelegate: DropDelegate {
    let model: AppModel

    func validateDrop(info: DropInfo) -> Bool {
        model.draggedAppID != nil
    }

    func dropEntered(info: DropInfo) {
        model.setDropAtEnd()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.finishDragging()
        return true
    }

    func dropExited(info: DropInfo) {
        model.clearEndDropTarget()
    }
}

private enum DropIndicatorEdge {
    case leading
    case trailing
}

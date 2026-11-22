import AppKit
import Foundation

final class DragAutoScroller {
    static let shared = DragAutoScroller()

    private weak var scrollView: NSScrollView?
    private var timer: Timer?
    private var mouseUpMonitor: Any?
    private var startedAt: TimeInterval = 0
    private var onEnd: (() -> Void)?

    private init() {}

    func attach(_ scrollView: NSScrollView) {
        self.scrollView = scrollView
    }

    func start(onEnd: @escaping () -> Void) {
        guard timer == nil else { return }
        self.onEnd = onEnd
        startedAt = CFAbsoluteTimeGetCurrent()

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.scrollIfNeeded()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.stop()
            return event
        }
    }

    func stop() {
        let completion = onEnd
        onEnd = nil
        timer?.invalidate()
        timer = nil

        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
            self.mouseUpMonitor = nil
        }

        if let completion {
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func scrollIfNeeded() {
        if NSEvent.pressedMouseButtons & 0x1 == 0 {
            stop()
            return
        }

        if CFAbsoluteTimeGetCurrent() - startedAt > 30 {
            stop()
            return
        }

        guard
            let scrollView,
            let documentView = scrollView.documentView,
            let window = scrollView.window
        else { return }

        let clipView = scrollView.contentView
        let viewportInWindow = clipView.convert(clipView.bounds, to: nil)
        let viewportOnScreen = window.convertToScreen(viewportInWindow)
        let mouse = NSEvent.mouseLocation
        let edge: CGFloat = 42

        let direction: CGFloat
        if mouse.y > viewportOnScreen.maxY - edge {
            direction = documentView.isFlipped ? -1 : 1
        } else if mouse.y < viewportOnScreen.minY + edge {
            direction = documentView.isFlipped ? 1 : -1
        } else {
            return
        }

        let maximumOffset = max(0, documentView.bounds.height - clipView.bounds.height)
        let currentOffset = clipView.bounds.origin.y
        let nextOffset = min(max(0, currentOffset + direction * 9), maximumOffset)
        guard nextOffset != currentOffset else { return }

        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: nextOffset))
        scrollView.reflectScrolledClipView(clipView)
    }
}

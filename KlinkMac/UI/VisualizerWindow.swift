// Borderless, click-through, always-on-top NSWindow hosting VisualizerView.
import AppKit
import SwiftUI

/// Creates and manages the lifecycle of the floating visualizer window.
@MainActor
final class VisualizerWindowController {
    enum Position: String, CaseIterable {
        case topLeft     = "tl"
        case topRight    = "tr"
        case bottomLeft  = "bl"
        case bottomRight = "br"

        var title: String {
            switch self {
            case .topLeft:     "Top left"
            case .topRight:    "Top right"
            case .bottomLeft:  "Bottom left"
            case .bottomRight: "Bottom right"
            }
        }
    }

    private var window: NSWindow?
    private var screenChangeObserver: Any?

    func show(appState: AppState) {
        if window?.isVisible == true {
            reposition(for: Position(rawValue: appState.settings.visualizerPosition) ?? .bottomRight)
            return
        }

        let view = VisualizerView(appState: appState)
            .fixedSize()
        let hosting = NSHostingView(rootView: view)
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let size = hosting.fittingSize
        let rect = NSRect(origin: .zero, size: size)

        let win = NSWindow(contentRect: rect,
                           styleMask: [.borderless],
                           backing: .buffered,
                           defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.ignoresMouseEvents = true
        win.isMovable = false
        win.isReleasedWhenClosed = false
        win.contentView = hosting
        win.orderFrontRegardless()

        window = win
        reposition(for: Position(rawValue: appState.settings.visualizerPosition) ?? .bottomRight)

        // Reposition when the screen resolution changes.
        // queue: .main means the handler runs on the main thread, so main-actor
        // state is safe to touch via MainActor.assumeIsolated.
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak appState] _ in
            MainActor.assumeIsolated {
                guard let self, let appState else { return }
                let raw = appState.settings.visualizerPosition
                self.reposition(for: Position(rawValue: raw) ?? .bottomRight)
            }
        }
    }

    func hide() {
        if let obs = screenChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            screenChangeObserver = nil
        }
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    func reposition(for position: Position) {
        guard let win = window, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        let size = win.frame.size
        let origin: NSPoint
        switch position {
        case .topLeft:
            origin = NSPoint(x: visible.minX + margin,
                             y: visible.maxY - size.height - margin)
        case .topRight:
            origin = NSPoint(x: visible.maxX - size.width - margin,
                             y: visible.maxY - size.height - margin)
        case .bottomLeft:
            origin = NSPoint(x: visible.minX + margin,
                             y: visible.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: visible.maxX - size.width - margin,
                             y: visible.minY + margin)
        }
        win.setFrameOrigin(origin)
    }

    var isVisible: Bool { window?.isVisible ?? false }
}

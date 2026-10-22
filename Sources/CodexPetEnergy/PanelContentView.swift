import AppKit
import SwiftUI

final class PanelContentView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private let menuProvider: () -> NSMenu
    private let dragDidEnd: () -> Void
    private let isCompact: () -> Bool
    private let activateCompactTarget: (EnergyPanelMode) -> Void
    private var pointerTracking: CompactPointerTracking?
    private var dragWindowOrigin: CGPoint = .zero
    private var trackingCompact = false

    init(
        rootView: Content,
        menuProvider: @escaping () -> NSMenu,
        dragDidEnd: @escaping () -> Void,
        isCompact: @escaping () -> Bool,
        activateCompactTarget: @escaping (EnergyPanelMode) -> Void
    ) {
        hostingView = NSHostingView(rootView: rootView)
        self.menuProvider = menuProvider
        self.dragDidEnd = dragDidEnd
        self.isCompact = isCompact
        self.activateCompactTarget = activateCompactTarget
        super.init(frame: .zero)
        addSubview(hostingView)
    }

    @MainActor required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    /// External commands arrive outside an AppKit input event; flush the hosting graph too.
    func refreshHostedContent() {
        hostingView.rootView = hostingView.rootView
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        // Leave hover, help, right-click and accessibility routing in SwiftUI.
        if let type = NSApp.currentEvent?.type,
           [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(type),
           isCompact() || pointerTracking != nil || isHeaderDragPoint(convert(point, from: superview)) {
            return self
        }
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        if let window, isCompact() || isHeaderDragPoint(convert(event.locationInWindow, from: nil)) {
            if event.modifierFlags.contains(.control) {
                rightMouseDown(with: event)
                return
            }
            trackingCompact = isCompact()
            pointerTracking = CompactPointerTracking(
                start: window.convertPoint(toScreen: event.locationInWindow),
                target: trackingCompact ? compactTarget(at: event.locationInWindow) : nil)
            dragWindowOrigin = window.frame.origin
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var tracking = pointerTracking, let window else {
            super.mouseDragged(with: event)
            return
        }
        guard isCompact() == trackingCompact else { pointerTracking = nil; return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        tracking.update(to: point)
        pointerTracking = tracking
        if tracking.isDragging {
            window.setFrameOrigin(CGPoint(x: dragWindowOrigin.x + point.x - tracking.start.x,
                                          y: dragWindowOrigin.y + point.y - tracking.start.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard var tracking = pointerTracking, let window else {
            super.mouseUp(with: event)
            return
        }
        pointerTracking = nil
        guard isCompact() == trackingCompact else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let target = tracking.finish(at: point, target: trackingCompact ? compactTarget(at: event.locationInWindow) : nil)
        if tracking.isDragging {
            window.setFrameOrigin(CGPoint(x: dragWindowOrigin.x + point.x - tracking.start.x,
                                          y: dragWindowOrigin.y + point.y - tracking.start.y))
            dragDidEnd()
        } else if let target {
            activateCompactTarget(target)
        }
    }

    private func compactTarget(at windowPoint: CGPoint) -> EnergyPanelMode? {
        func find(in view: NSView) -> EnergyPanelMode? {
            guard !view.isHidden else { return nil }
            if let region = view as? CompactActionRegionView,
               region.bounds.contains(region.convert(windowPoint, from: nil)) {
                return region.target
            }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        return find(in: hostingView)
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
    }

    private func isHeaderDragPoint(_ point: CGPoint) -> Bool {
        func find(in view: NSView) -> Bool {
            guard !view.isHidden else { return false }
            if let region = view as? PanelDragRegionView {
                return region.bounds.contains(region.convert(point, from: self))
            }
            return view.subviews.contains { find(in: $0) }
        }
        return find(in: hostingView)
    }

}

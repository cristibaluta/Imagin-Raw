//
//  KeyEventInterceptor.swift
//  Imagin Raw
//
//  Invisible NSView that installs a local NSEvent monitor to intercept
//  arrow keys before NSScrollView can consume them.
//

#if os(macOS)
import SwiftUI
import AppKit

struct KeyEventInterceptor: NSViewRepresentable {
    let onLeft: () -> Void
    let onRight: () -> Void

    func makeNSView(context: Context) -> InterceptorNSView {
        let view = InterceptorNSView()
        view.onLeft = onLeft
        view.onRight = onRight
        return view
    }

    func updateNSView(_ nsView: InterceptorNSView, context: Context) {
        nsView.onLeft = onLeft
        nsView.onRight = onRight
    }
}

class InterceptorNSView: NSView {
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let existing = monitor {
            NSEvent.removeMonitor(existing)
            monitor = nil
        }
        guard window != nil else {
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            switch event.keyCode {
                case 123: // left arrow
                    self.onLeft?()
                    return nil
                case 124: // right arrow
                    self.onRight?()
                    return nil
                default:
                    return event
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        if newWindow == nil, let existing = monitor {
            NSEvent.removeMonitor(existing)
            monitor = nil
        }
    }
}
#endif

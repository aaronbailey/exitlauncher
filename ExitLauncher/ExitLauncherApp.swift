import SwiftUI
import AppKit
import Combine

enum RocketState {
    case offline     // no ready nodes — transparent fill
    case ready       // has ready nodes but not using one — yellow fill
    case connected   // actively using an exit node — green fill
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var instanceManager = InstanceManager()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 22)

        if let button = statusItem.button {
            button.image = makeRocketIcon(state: .offline)
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(instanceManager)
        )

        // Watch for state changes
        Publishers.CombineLatest(
            instanceManager.$currentExitNode,
            instanceManager.$instances
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] exitNode, instances in
            let state: RocketState
            if exitNode != nil {
                state = .connected
            } else if instances.contains(where: { $0.status == .ready }) {
                state = .ready
            } else {
                state = .offline
            }
            self?.statusItem.button?.image = self?.makeRocketIcon(state: state)
        }
        .store(in: &cancellables)
    }

    private func makeRocketIcon(state: RocketState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            let strokeWidth: CGFloat = 1.3

            // Entire icon is one color — changes by state
            let color: NSColor
            switch state {
            case .offline:
                color = NSColor.labelColor // white in dark mode, black in light
            case .ready:
                color = NSColor.systemYellow
            case .connected:
                color = NSColor.systemGreen
            }

            color.setStroke()

            // Rocket pointing up-right (~40° tilt)
            ctx.saveGState()
            ctx.translateBy(x: 9, y: 9)
            ctx.rotate(by: -.pi / 4.5)
            ctx.translateBy(x: -9, y: -9)

            // --- Rocket body ---
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 9, y: 17.5))
            body.curve(to: NSPoint(x: 12.2, y: 6.5),
                       controlPoint1: NSPoint(x: 11.8, y: 15),
                       controlPoint2: NSPoint(x: 12.8, y: 10))
            body.curve(to: NSPoint(x: 5.8, y: 6.5),
                       controlPoint1: NSPoint(x: 10.8, y: 4.8),
                       controlPoint2: NSPoint(x: 7.2, y: 4.8))
            body.curve(to: NSPoint(x: 9, y: 17.5),
                       controlPoint1: NSPoint(x: 5.2, y: 10),
                       controlPoint2: NSPoint(x: 6.2, y: 15))
            body.close()
            body.lineWidth = strokeWidth
            body.stroke()

            // --- Left fin ---
            let leftFin = NSBezierPath()
            leftFin.move(to: NSPoint(x: 6, y: 7.5))
            leftFin.line(to: NSPoint(x: 3, y: 4.5))
            leftFin.line(to: NSPoint(x: 5, y: 4.5))
            leftFin.line(to: NSPoint(x: 6.8, y: 6))
            leftFin.close()
            leftFin.lineWidth = strokeWidth
            leftFin.stroke()

            // --- Right fin ---
            let rightFin = NSBezierPath()
            rightFin.move(to: NSPoint(x: 12, y: 7.5))
            rightFin.line(to: NSPoint(x: 15, y: 4.5))
            rightFin.line(to: NSPoint(x: 13, y: 4.5))
            rightFin.line(to: NSPoint(x: 11.2, y: 6))
            rightFin.close()
            rightFin.lineWidth = strokeWidth
            rightFin.stroke()

            // --- Exhaust flames ---
            let flame1 = NSBezierPath()
            flame1.move(to: NSPoint(x: 7.8, y: 5.5))
            flame1.line(to: NSPoint(x: 7.3, y: 2.5))
            flame1.lineWidth = strokeWidth
            flame1.stroke()

            let flame2 = NSBezierPath()
            flame2.move(to: NSPoint(x: 9, y: 5))
            flame2.line(to: NSPoint(x: 9, y: 1.5))
            flame2.lineWidth = strokeWidth
            flame2.stroke()

            let flame3 = NSBezierPath()
            flame3.move(to: NSPoint(x: 10.2, y: 5.5))
            flame3.line(to: NSPoint(x: 10.7, y: 2.5))
            flame3.lineWidth = strokeWidth
            flame3.stroke()

            ctx.restoreGState()

            return true
        }
        // Non-template so yellow/green render as actual colors
        image.isTemplate = false
        return image
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct ExitLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

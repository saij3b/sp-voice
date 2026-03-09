import Cocoa

/// Manages the NSStatusItem and its menu/popover.
/// In Phase 2 this is mostly a placeholder — the real menu bar UI is driven
/// by SwiftUI's MenuBarExtra in SPVoiceApp.swift.
/// This class exists for scenarios requiring programmatic NSStatusItem control
/// (e.g. dynamic icon updates, click handling outside SwiftUI).
@MainActor
final class StatusBarController {

    private var statusItem: NSStatusItem?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "SP Voice")
        statusItem = item
    }

    func updateIcon(for state: DictationState) {
        let name = state.menuBarIcon
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: state.statusText)
    }

    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

import AppKit
import os

/// Manages clipboard save/restore for the paste-fallback insertion strategy.
/// Full implementation in Phase 4.
enum PasteboardHelper {

    struct SavedClipboard {
        let changeCount: Int
        let items: [(NSPasteboard.PasteboardType, Data)]
    }

    /// Save the current clipboard contents so they can be restored after paste.
    static func saveClipboard() -> SavedClipboard {
        let pb = NSPasteboard.general
        let changeCount = pb.changeCount
        var items: [(NSPasteboard.PasteboardType, Data)] = []

        for item in pb.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type) {
                    items.append((type, data))
                }
            }
        }
        return SavedClipboard(changeCount: changeCount, items: items)
    }

    /// Restore previously saved clipboard contents if nobody else has written
    /// to the clipboard since our save.
    static func restoreClipboard(_ saved: SavedClipboard) {
        let pb = NSPasteboard.general
        // Only restore if the clipboard hasn't been modified by another app
        guard pb.changeCount == saved.changeCount + 1 else {
            Logger.insertion.debug("Clipboard modified externally — skipping restore")
            return
        }

        pb.clearContents()
        for (type, data) in saved.items {
            pb.setData(data, forType: type)
        }
    }

    /// Set the clipboard to a plain text string.
    static func setClipboardText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

import AppKit

@MainActor
protocol ClipboardPasteboard: AnyObject {
    func snapshotItems() -> [NSPasteboardItem]
    @discardableResult
    func clearContents() -> Int
    func writeString(_ string: String) -> Bool
    func restoreItems(_ items: [NSPasteboardItem]) -> Bool
}

extension NSPasteboard: ClipboardPasteboard {
    func snapshotItems() -> [NSPasteboardItem] {
        pasteboardItems ?? []
    }

    func writeString(_ string: String) -> Bool {
        setString(string, forType: .string)
    }

    func restoreItems(_ items: [NSPasteboardItem]) -> Bool {
        writeObjects(items)
    }
}

@MainActor
final class ClipboardService {
    static var system: ClipboardService {
        ClipboardService(pasteboard: NSPasteboard.general)
    }

    private let pasteboard: ClipboardPasteboard

    init(pasteboard: ClipboardPasteboard) {
        self.pasteboard = pasteboard
    }

    func copy(_ text: String) -> Bool {
        let existingItems = pasteboard.snapshotItems()
        pasteboard.clearContents()

        guard pasteboard.writeString(text) else {
            pasteboard.clearContents()
            if !existingItems.isEmpty {
                _ = pasteboard.restoreItems(existingItems)
            }
            return false
        }

        return true
    }
}

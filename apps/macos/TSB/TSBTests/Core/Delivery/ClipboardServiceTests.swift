import AppKit
import XCTest
@testable import TSB

@MainActor
final class ClipboardServiceTests: XCTestCase {
    func testSuccessfulCopyWritesNewTextOnceWithoutRestoringPreviousItems() {
        let pasteboard = InMemoryPasteboard(items: [stringItem("previous"), dataItem()])

        XCTAssertTrue(ClipboardService(pasteboard: pasteboard).copy("new"))

        XCTAssertEqual(pasteboard.stringWriteCount, 1)
        XCTAssertEqual(pasteboard.restoreWriteCount, 0)
        XCTAssertEqual(pasteboard.items.count, 1)
        XCTAssertEqual(pasteboard.items[0].string(forType: .string), "new")
    }

    func testFailedCopyRestoresAllExistingItemsAfterOneNewTextAttempt() {
        let pasteboard = InMemoryPasteboard(items: [stringItem("previous"), dataItem()])
        pasteboard.failNextStringWrite = true

        XCTAssertFalse(ClipboardService(pasteboard: pasteboard).copy("new"))

        XCTAssertEqual(pasteboard.stringWriteCount, 1)
        XCTAssertEqual(pasteboard.restoreWriteCount, 1)
        XCTAssertEqual(pasteboard.items.count, 2)
        XCTAssertEqual(pasteboard.items[0].string(forType: .string), "previous")
        XCTAssertEqual(pasteboard.items[1].data(forType: Self.customType), Data([0x01, 0x02]))
    }

    private static let customType = NSPasteboard.PasteboardType("com.tsb.tests.payload")

    private func stringItem(_ value: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(value, forType: .string)
        return item
    }

    private func dataItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(Data([0x01, 0x02]), forType: Self.customType)
        return item
    }
}

@MainActor
private final class InMemoryPasteboard: ClipboardPasteboard {
    var items: [NSPasteboardItem]
    var failNextStringWrite = false
    private(set) var stringWriteCount = 0
    private(set) var restoreWriteCount = 0

    init(items: [NSPasteboardItem]) {
        self.items = items
    }

    func snapshotItems() -> [NSPasteboardItem] {
        items
    }

    func clearContents() -> Int {
        items = []
        return 1
    }

    func writeString(_ string: String) -> Bool {
        stringWriteCount += 1
        guard !failNextStringWrite else {
            failNextStringWrite = false
            return false
        }
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        items = [item]
        return true
    }

    func restoreItems(_ items: [NSPasteboardItem]) -> Bool {
        restoreWriteCount += 1
        self.items = items
        return true
    }
}

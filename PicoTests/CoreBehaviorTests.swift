import XCTest
@testable import Pico

final class CoreBehaviorTests: XCTestCase {
    func testClassifierRecognizesURLCodeColorAndPlainText() {
        XCTAssertEqual(ClipboardClassifier.classify("https://openai.com"), .link)
        XCTAssertEqual(ClipboardClassifier.classify("let value = 42"), .code)
        XCTAssertEqual(ClipboardClassifier.classify("#59C7FF"), .color)
        XCTAssertEqual(ClipboardClassifier.classify("普通文本"), .text)
    }

    func testTranslationDirectionUsesChinesePresenceOnlyAfterExplicitRequest() {
        XCTAssertEqual(TranslationDirection.forText("你好 Pico"), .english)
        XCTAssertEqual(TranslationDirection.forText("hello Pico"), .simplifiedChinese)
    }

    func testRetentionPolicyNeverExpiresFavorites() {
        let oldDate = Date(timeIntervalSinceNow: -400 * 86_400)
        XCTAssertFalse(HistoryRetentionPolicy.month.shouldDelete(createdAt: oldDate, isFavorite: true, now: Date()))
        XCTAssertTrue(HistoryRetentionPolicy.month.shouldDelete(createdAt: oldDate, isFavorite: false, now: Date()))
        XCTAssertFalse(HistoryRetentionPolicy.forever.shouldDelete(createdAt: oldDate, isFavorite: false, now: Date()))
    }

    @MainActor
    func testRepositoryDeduplicatesAndSupportsMultipleGroups() {
        let repository = ClipboardRepository(inMemory: true)
        let first = repository.capture(text: "same")!
        let second = repository.capture(text: "same")!
        XCTAssertEqual(first.id, second.id)
        repository.addGroup(name: "开发")
        repository.addGroup(name: "常用")
        repository.add(first, to: repository.groups[0])
        repository.add(first, to: repository.groups[1])
        XCTAssertEqual(repository.groupsContaining(first).count, 2)
    }
}

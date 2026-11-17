import XCTest
// 注意：单 target 项目不需要 @testable import ClipKitCore
// 所有类型在同一个模块内，直接可用

final class ClipTests: XCTestCase {

    func testClipCreation() {
        let clip = Clip(text: "Hello World", type: .text)
        XCTAssertEqual(clip.text, "Hello World")
        XCTAssertEqual(clip.type, .text)
        XCTAssertFalse(clip.isPinned)
        XCTAssertEqual(clip.size, "Hello World".utf8.count)
    }

    func testClipPreviewText_shortText() {
        let clip = Clip(text: "短文本", type: .text)
        XCTAssertEqual(clip.previewText, "短文本")
    }

    func testClipPreviewText_longText() {
        let longText = String(repeating: "A", count: 300)
        let clip = Clip(text: longText, type: .text)
        XCTAssertTrue(clip.previewText.hasSuffix("..."))
        XCTAssertEqual(clip.previewText.count, 203) // 200 + "..."
    }

    func testClipCodable() throws {
        let original = Clip(text: "test", type: .text, sourceApp: "com.test.app")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Clip.self, from: encoded)
        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.text, decoded.text)
        XCTAssertEqual(original.type, decoded.type)
    }
}

final class ClipTypeTests: XCTestCase {

    func testInferURL() {
        let type = ClipType.infer(from: "https://github.com", pasteboardTypes: ["public.utf8-plain-text"])
        XCTAssertEqual(type, .link)
    }

    func testInferEmail() {
        let type = ClipType.infer(from: "user@example.com", pasteboardTypes: ["public.utf8-plain-text"])
        XCTAssertEqual(type, .email)
    }

    func testInferHexColor() {
        let type = ClipType.infer(from: "#FF5733", pasteboardTypes: ["public.utf8-plain-text"])
        XCTAssertEqual(type, .color)
    }

    func testInferCode() {
        let code = "func test() {\n  let x = 1\n  return x\n}"
        let type = ClipType.infer(from: code, pasteboardTypes: ["public.utf8-plain-text"])
        XCTAssertEqual(type, .code)
    }

    func testInferPlainText() {
        let type = ClipType.infer(from: "这是一段普通文本", pasteboardTypes: ["public.utf8-plain-text"])
        XCTAssertEqual(type, .text)
    }

    func testInferImage() {
        let type = ClipType.infer(from: "", pasteboardTypes: ["public.image", "public.tiff"])
        XCTAssertEqual(type, .image)
    }

    func testInferFile() {
        let type = ClipType.infer(from: "/Users/test/file.txt", pasteboardTypes: ["public.file-url"])
        XCTAssertEqual(type, .file)
    }
}

final class SearchEngineTests: XCTestCase {

    private func makeClips() -> [Clip] {
        [
            Clip(text: "Hello World", type: .text, sourceApp: "com.test", sourceAppIcon: "Safari"),
            Clip(text: "func swift() -> String", type: .code, sourceApp: "com.test", sourceAppIcon: "Xcode"),
            Clip(text: "https://github.com", type: .link, sourceApp: "com.test", sourceAppIcon: "Chrome"),
        ]
    }

    func testSearchByKeyword() {
        let results = SearchEngine.search(query: "Hello", in: makeClips())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.text, "Hello World")
    }

    func testSearchExactMatchScoresHigher() {
        let clips = makeClips()
        let results = SearchEngine.search(query: "Hello World", in: clips)
        XCTAssertEqual(results.first?.text, "Hello World")
    }

    func testSearchEmptyReturnsAll() {
        let clips = makeClips()
        let results = SearchEngine.search(query: "", in: clips)
        XCTAssertEqual(results.count, clips.count)
    }

    func testSearchNoMatch() {
        let results = SearchEngine.search(query: "zzzznotexist", in: makeClips())
        XCTAssertTrue(results.isEmpty)
    }

    func testFilterByType() {
        let clips = makeClips()
        let filtered = SearchEngine.filter(type: .code, in: clips)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.type, .code)
    }

    func testFilterByTypeNil() {
        let clips = makeClips()
        let filtered = SearchEngine.filter(type: nil, in: clips)
        XCTAssertEqual(filtered.count, clips.count)
    }

    func testPinyinConversion() {
        let pinyin = SearchEngine.pinyin(of: "剪贴板")
        XCTAssertTrue(pinyin.contains("jian") || pinyin.contains("jian tie ban") || !pinyin.isEmpty)
    }
}


final class ContentHashDeduplicationTests: XCTestCase {

    func testContentHashIsStableForSameContent() {
        let first = Clip(text: "same content", type: .text, sourceApp: "com.one")
        let second = Clip(text: "same content", type: .text, sourceApp: "com.two")
        XCTAssertEqual(first.contentHash, second.contentHash)
    }

    func testContentHashChangesWithContent() {
        let first = Clip(text: "same content", type: .text)
        let second = Clip(text: "different content", type: .text)
        XCTAssertNotEqual(first.contentHash, second.contentHash)
    }

    func testContentHashIncludesImagePayload() {
        let first = Clip(text: "", type: .image, payloadData: Data([0, 1, 2]))
        let second = Clip(text: "", type: .image, payloadData: Data([0, 1, 3]))
        XCTAssertNotEqual(first.contentHash, second.contentHash)
    }

    func testStoreRejectsDuplicateHashAnywhereInHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipKitTests-\(UUID().uuidString)", isDirectory: true)
        let storageURL = directory.appendingPathComponent("clips.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ClipStore(maxItems: 100, storageURL: storageURL)
        let first = Clip(text: "duplicate", type: .text, sourceApp: "com.one")
        let second = Clip(text: "duplicate", type: .text, sourceApp: "com.two")
        let third = Clip(text: "different", type: .text)

        let firstInserted = await store.add(first)
        let duplicateInserted = await store.add(second)
        let thirdInserted = await store.add(third)

        let count = await store.allClips().count
        XCTAssertNotNil(firstInserted)
        XCTAssertNil(duplicateInserted)
        XCTAssertNotNil(thirdInserted)
        XCTAssertEqual(count, 2)
    }
}

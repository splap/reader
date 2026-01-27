import XCTest
@testable import ReaderCore

final class CFITests: XCTestCase {
    func testParseBaseCFI() {
        // Test basic CFI parsing
        let result = CFIParser.parseBaseCFI("epubcfi(/6/4[ch02]!)")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.spineIndex, 1)
        XCTAssertEqual(result?.idref, "ch02")

        // Test without idref
        let result2 = CFIParser.parseBaseCFI("epubcfi(/6/2!)")
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2?.spineIndex, 0)
        XCTAssertNil(result2?.idref)

        // Test invalid CFI
        XCTAssertNil(CFIParser.parseBaseCFI("invalid"))
        XCTAssertNil(CFIParser.parseBaseCFI("epubcfi(/5/4!)"))  // Wrong step (5 instead of 6)
    }

    func testGenerateBaseCFI() {
        let cfi1 = CFIParser.generateBaseCFI(spineIndex: 1, idref: "ch02")
        XCTAssertEqual(cfi1, "epubcfi(/6/4[ch02]!)")

        let cfi2 = CFIParser.generateBaseCFI(spineIndex: 0)
        XCTAssertEqual(cfi2, "epubcfi(/6/2!)")

        let cfi3 = CFIParser.generateBaseCFI(spineIndex: 3)
        XCTAssertEqual(cfi3, "epubcfi(/6/8!)")
    }

    func testParseFullCFI() {
        // Test full CFI with DOM path and character offset
        let result = CFIParser.parseFullCFI("epubcfi(/6/4[ch02]!/4/2/1:42)")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.spineIndex, 1)
        XCTAssertEqual(result?.idref, "ch02")
        XCTAssertEqual(result?.domPath, [1, 0])  // /4/2 -> [1, 0] (even steps to 0-based)
        XCTAssertEqual(result?.charOffset, 42)

        // Test without character offset
        let result2 = CFIParser.parseFullCFI("epubcfi(/6/2!/4/2)")
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2?.spineIndex, 0)
        XCTAssertEqual(result2?.domPath, [1, 0])
        XCTAssertNil(result2?.charOffset)

        // Test base-only CFI (no content path)
        let result3 = CFIParser.parseFullCFI("epubcfi(/6/8[chapter3]!)")
        XCTAssertNotNil(result3)
        XCTAssertEqual(result3?.spineIndex, 3)
        XCTAssertEqual(result3?.idref, "chapter3")
        XCTAssertEqual(result3?.domPath, [])
        XCTAssertNil(result3?.charOffset)
    }

    func testGenerateFullCFI() {
        let cfi1 = CFIParser.generateFullCFI(spineIndex: 1, idref: "ch02", domPath: [1, 0, 0], charOffset: 42)
        XCTAssertEqual(cfi1, "epubcfi(/6/4[ch02]!/4/2/2:42)")

        let cfi2 = CFIParser.generateFullCFI(spineIndex: 0, domPath: [1, 0])
        XCTAssertEqual(cfi2, "epubcfi(/6/2!/4/2)")

        let cfi3 = CFIParser.generateFullCFI(spineIndex: 2)
        XCTAssertEqual(cfi3, "epubcfi(/6/6!)")
    }

    func testCFIRoundTrip() {
        // Test that parsing and generating gives consistent results
        let original = ParsedFullCFI(spineIndex: 2, idref: "section-5", domPath: [0, 3, 1], charOffset: 100)
        let generated = CFIParser.generateFullCFI(
            spineIndex: original.spineIndex,
            idref: original.idref,
            domPath: original.domPath,
            charOffset: original.charOffset
        )
        let parsed = CFIParser.parseFullCFI(generated)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.spineIndex, original.spineIndex)
        XCTAssertEqual(parsed?.idref, original.idref)
        XCTAssertEqual(parsed?.domPath, original.domPath)
        XCTAssertEqual(parsed?.charOffset, original.charOffset)
    }

    func testCFIPositionSpineIndex() {
        let position = CFIPosition(bookId: "book1", cfi: "epubcfi(/6/4[ch02]!/4/2:10)")
        XCTAssertEqual(position.spineIndex, 1)

        let position2 = CFIPosition(bookId: "book1", cfi: "epubcfi(/6/8!)")
        XCTAssertEqual(position2.spineIndex, 3)

        let invalidPosition = CFIPosition(bookId: "book1", cfi: "invalid")
        XCTAssertNil(invalidPosition.spineIndex)
    }

    func testCFIPositionStoreRoundTrip() {
        let suiteName = "ReaderCoreTests.CFIPositionStore"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsCFIPositionStore(defaults: defaults)
        let position = CFIPosition(
            bookId: "book1",
            cfi: "epubcfi(/6/4[ch02]!/4/2:42)",
            maxCfi: "epubcfi(/6/8!/2/4:100)"
        )
        store.save(position)

        let loaded = store.load(bookId: "book1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.cfi, position.cfi)
        XCTAssertEqual(loaded?.maxCfi, position.maxCfi)
    }
}

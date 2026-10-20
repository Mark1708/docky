import XCTest
@testable import Docky

final class FoundationModelLocalePolicyTests: XCTestCase {
    func testRussianAndEnglishInstructionsNameRequestedLanguage() {
        let russian = FoundationModelLocalePolicy(languageIdentifier: "ru-RU")
        let english = FoundationModelLocalePolicy(languageIdentifier: "en-US")

        XCTAssertEqual(russian.englishLanguageName, "Russian")
        XCTAssertEqual(english.englishLanguageName, "English")
        XCTAssertTrue(russian.responseInstruction.contains("folder title in Russian"))
        XCTAssertTrue(english.responseInstruction.contains("folder title in English"))
    }

    func testInstructionPreservesStructuralTokens() {
        let instruction = FoundationModelLocalePolicy(languageIdentifier: "ru").responseInstruction
        let tokens = [
            "kind",
            "bundleIdentifier",
            "bundleIdentifiers",
            "widgetKind",
            "widgetOwnerBundleIdentifier",
            "widgetSpan",
            "owner",
        ]

        for token in tokens {
            XCTAssertTrue(instruction.contains(token), "Missing structural token: \(token)")
        }
        XCTAssertTrue(instruction.contains("Do not translate or rewrite those structural tokens."))
    }
}

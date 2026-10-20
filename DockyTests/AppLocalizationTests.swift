import XCTest
@testable import Docky

final class AppLocalizationTests: XCTestCase {
    func testEffectiveLanguageSelectionAndEnglishFallback() {
        let available = ["en", "es", "ru"]

        XCTAssertEqual(selection("ru-RU", available: available), "ru")
        XCTAssertEqual(selection("en-US", available: available), "en")
        XCTAssertEqual(selection("es-ES", available: available), "es")
        XCTAssertEqual(selection("de-DE", available: available), "en")
    }

    func testMissingSemanticKeyUsesLiteralFallback() {
        XCTAssertEqual(
            AppLocalization.string(
                key: "test.missing.semantic-key",
                fallback: "Literal fallback",
                table: "MenuCatalog"
            ),
            "Literal fallback"
        )
    }

    func testAppHostUsesExplicitTestModeMarker() {
        XCTAssertTrue(AppDelegate.isRunningTests)
    }

    private func selection(_ preferred: String, available: [String]) -> String {
        AppLocalization.effectiveLanguageIdentifier(
            preferredLanguages: [preferred],
            availableLocalizations: available,
            developmentLocalization: "en"
        )
    }
}

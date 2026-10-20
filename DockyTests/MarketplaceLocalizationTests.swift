import XCTest
@testable import Docky

final class MarketplaceLocalizationTests: XCTestCase {
    func testLocalizedMetadataFallsBackIndependentlyPerField() throws {
        let data = Data("""
        [{
          "identifier": "com.example.widget",
          "title": "Base title",
          "author": "Example",
          "version": "1.0",
          "downloadURL": "https://example.com/widget.zip",
          "description": "Base description",
          "localizations": {
            "en": {"title": "English title", "description": "English description"},
            "ru": {"title": "Русское название"}
          }
        }]
        """.utf8)
        let widget = try XCTUnwrap(JSONDecoder().decode([MarketplaceWidget].self, from: data).first)

        XCTAssertEqual(widget.localizedTitle(languageIdentifier: "ru-RU"), "Русское название")
        XCTAssertEqual(widget.localizedDescription(languageIdentifier: "ru-RU"), "English description")
        XCTAssertEqual(widget.localizedTitle(languageIdentifier: "de-DE"), "English title")
        XCTAssertEqual(widget.identifier, "com.example.widget")
        XCTAssertEqual(widget.downloadURL.absoluteString, "https://example.com/widget.zip")
    }

    func testBaseMetadataIsFinalPerFieldFallback() throws {
        let data = Data("""
        [{
          "identifier": "com.example.partial",
          "title": "Base title",
          "author": "Example",
          "version": "1.0",
          "downloadURL": "https://example.com/widget.zip",
          "description": "Base description",
          "localizations": {"ru": {"title": "Русское название"}}
        }]
        """.utf8)
        let widget = try XCTUnwrap(JSONDecoder().decode([MarketplaceWidget].self, from: data).first)

        XCTAssertEqual(widget.localizedTitle(languageIdentifier: "ru"), "Русское название")
        XCTAssertEqual(widget.localizedDescription(languageIdentifier: "ru"), "Base description")
    }
}

import Foundation
import XCTest
@testable import Docky

final class LocalizedNumberInputTests: XCTestCase {
    func testRussianAndEnglishDecimalSeparators() {
        XCTAssertEqual(LocalizedNumberInput.format(1.5, locale: Locale(identifier: "ru_RU")), "1,5")
        XCTAssertEqual(LocalizedNumberInput.format(1.5, locale: Locale(identifier: "en_US")), "1.5")
        XCTAssertEqual(LocalizedNumberInput.parse("1,5", locale: Locale(identifier: "ru_RU")), 1.5)
        XCTAssertEqual(LocalizedNumberInput.parse("1.5", locale: Locale(identifier: "en_US")), 1.5)
    }

    func testNumericRoundTrip() throws {
        for localeIdentifier in ["ru_RU", "en_US"] {
            let locale = Locale(identifier: localeIdentifier)
            let text = LocalizedNumberInput.format(22.25, locale: locale)
            XCTAssertEqual(try XCTUnwrap(LocalizedNumberInput.parse(text, locale: locale)), 22.25)
        }
    }
}

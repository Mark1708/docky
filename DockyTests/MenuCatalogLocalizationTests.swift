import XCTest
@testable import Docky

final class MenuCatalogLocalizationTests: XCTestCase {
    func testCatalogDecodesAllActionsAndLocalizationMetadata() throws {
        let actions: CatalogActionsDocument = try decodeResource("actions")
        let definitions = actions.packages.flatMap(\.actions)

        XCTAssertEqual(definitions.count, 40)
        XCTAssertTrue(definitions.allSatisfy { !($0.titleLocalizationKey ?? "").isEmpty })

        let quit = try XCTUnwrap(definitions.first { $0.id == "app.quit" })
        XCTAssertEqual(quit.alternateTitle, "Force Quit")
        XCTAssertEqual(quit.alternateTitleLocalizationKey, "catalog.action.app.quit.alternate-title")

        XCTAssertEqual(actions.packages.map(\.titleLocalizationKey), [
            "catalog.package.docky.core.title",
            "catalog.package.docky.curated-app-integrations.title",
        ])
        XCTAssertTrue(actions.packages.allSatisfy { !($0.descriptionLocalizationKey ?? "").isEmpty })
    }

    func testOptionsIdentityAndOperationalMenuPathsRemainStable() throws {
        let menus: CatalogMenusDocument = try decodeResource("menus")
        let appMenu = try XCTUnwrap(menus.menus.first { $0.tileType == .app })
        let options = try XCTUnwrap(appMenu.items.first { $0.id == "app.options" })
        XCTAssertEqual(options.titleLocalizationKey, "catalog.menu.app.options.title")

        let actions: CatalogActionsDocument = try decodeResource("actions")
        let definitions = actions.packages.flatMap(\.actions)
        let xcodeRun = try XCTUnwrap(definitions.first { $0.id == "xcode.run" })
        XCTAssertEqual(xcodeRun.targetApp, "com.apple.dt.Xcode")
        XCTAssertEqual(xcodeRun.path, ["Product", "Run"])
        let safariPrivate = try XCTUnwrap(definitions.first { $0.id == "safari.new-private-window" })
        XCTAssertEqual(safariPrivate.path, ["File", "New Private Window"])
    }

    func testMissingCatalogTranslationFallsBackPerKey() {
        XCTAssertEqual(
            AppLocalization.string(
                key: "catalog.test.missing",
                fallback: "Fallback title",
                table: "MenuCatalog"
            ),
            "Fallback title"
        )
    }

    private func decodeResource<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "MenuCatalog")
                ?? Bundle.main.url(forResource: name, withExtension: "json")
        )
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

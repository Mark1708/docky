import Foundation
import XCTest
@testable import Docky

final class ExternalWidgetSettingsManifestTests: XCTestCase {
    func testEffectiveEnglishLiteralAndIdentifierFallbacksPreserveSchema() throws {
        let bundle = try makeFixtureBundle()
        let fields = ExternalWidgetSettingsManifest.load(
            from: bundle,
            languageIdentifier: "ru-RU"
        )

        XCTAssertEqual(fields.map(\.id), ["name", "mode", "literal", "identifier", "enabled", "scale"])
        XCTAssertEqual(fields.map(\.label), [
            "Имя",
            "Mode",
            "Literal label",
            "identifier",
            "Enabled",
            "Scale",
        ])

        let mode = try XCTUnwrap(fields.first { $0.id == "mode" })
        XCTAssertEqual(mode.defaultValue, .string("fast"))
        XCTAssertEqual(mode.options, [
            .init(value: "fast", label: "Fast"),
            .init(value: "slow", label: "Slow literal"),
            .init(value: "raw", label: "raw"),
        ])

        XCTAssertEqual(fields.first { $0.id == "enabled" }?.defaultValue, .bool(true))
        XCTAssertEqual(fields.first { $0.id == "scale" }?.defaultValue, .number(1.5))
    }

    func testMalformedFieldsAreSkippedWithoutChangingValidValues() throws {
        let bundle = try makeFixtureBundle()
        let fields = ExternalWidgetSettingsManifest.load(from: bundle, languageIdentifier: "de-DE")

        XCTAssertEqual(fields.count, 6)
        XCTAssertFalse(fields.contains { $0.id.isEmpty })
        XCTAssertEqual(fields.first { $0.id == "name" }?.label, "Name")
        XCTAssertEqual(fields.first { $0.id == "mode" }?.options?.map(\.value), ["fast", "slow", "raw"])
    }

    private func makeFixtureBundle() throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockyManifestTests-\(UUID().uuidString).bundle", isDirectory: true)
        let resources = root.appendingPathComponent("Contents/Resources", isDirectory: true)
        let english = resources.appendingPathComponent("en.lproj", isDirectory: true)
        let russian = resources.appendingPathComponent("ru.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: russian, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.DockyManifestTests.\(UUID().uuidString)",
            "CFBundleName": "DockyManifestTests",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "1",
            "CFBundleDevelopmentRegion": "en",
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: root.appendingPathComponent("Contents/Info.plist"))

        let manifest = """
        {
          "fields": [
            {"id":"name","label":"Name literal","labelKey":"field.name","type":"text","default":"Docky"},
            {"id":"mode","labelKey":"field.mode","type":"select","default":"fast","options":[
              {"value":"fast","labelKey":"option.fast"},
              {"value":"slow","label":"Slow literal"},
              {"value":"raw"},
              {"label":"Missing value"}
            ]},
            {"id":"literal","label":"Literal label","type":"text"},
            {"id":"identifier","type":"text"},
            {"id":"enabled","labelKey":"field.enabled","type":"toggle","default":true},
            {"id":"scale","labelKey":"field.scale","type":"number","default":1.5},
            {"label":"Missing id","type":"text"},
            {"id":"bad-type","label":"Bad type","type":"color"}
          ]
        }
        """
        try Data(manifest.utf8).write(to: resources.appendingPathComponent("settings.json"))

        let englishStrings = """
        "field.name" = "Name";
        "field.mode" = "Mode";
        "field.enabled" = "Enabled";
        "field.scale" = "Scale";
        "option.fast" = "Fast";
        """
        let russianStrings = """
        "field.name" = "Имя";
        """
        try Data(englishStrings.utf8).write(to: english.appendingPathComponent("DockyWidget.strings"))
        try Data(russianStrings.utf8).write(to: russian.appendingPathComponent("DockyWidget.strings"))

        return try XCTUnwrap(Bundle(url: root))
    }
}

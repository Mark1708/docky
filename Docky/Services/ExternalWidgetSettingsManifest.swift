//
//  ExternalWidgetSettingsManifest.swift
//  Docky
//

import Foundation

enum ExternalWidgetSettingsManifest {
    static let resourceName = "settings"
    static let resourceExtension = "json"

    static func load(
        from bundle: Bundle,
        languageIdentifier: String
    ) -> [WidgetSettingsField] {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        return parse(data) { key in
            let missingValue = "__DOCKY_MISSING_LOCALIZATION__"
            let value = ExternalWidgetLocalization.string(
                key: key,
                fallback: missingValue,
                bundle: bundle,
                languageIdentifier: languageIdentifier
            )
            return value == missingValue ? nil : value
        }
    }

    static func parse(
        _ data: Data,
        localize: (String) -> String?
    ) -> [WidgetSettingsField] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawFields = root["fields"] as? [[String: Any]] else {
            return []
        }
        return rawFields.compactMap { parseField($0, localize: localize) }
    }

    private static func parseField(
        _ dict: [String: Any],
        localize: (String) -> String?
    ) -> WidgetSettingsField? {
        guard let id = (dict["id"] as? String), !id.isEmpty,
              let typeRaw = dict["type"] as? String,
              let type = WidgetSettingsField.FieldType(rawValue: typeRaw) else {
            return nil
        }

        let label = localizedLabel(
            key: dict["labelKey"] as? String,
            literal: dict["label"] as? String,
            fallback: id,
            localize: localize
        )
        let defaultValue = parseDefault(dict["default"], type: type)

        let options: [WidgetSettingsField.Option]?
        if type == .select, let rawOptions = dict["options"] as? [[String: Any]] {
            options = rawOptions.compactMap { option in
                guard let value = option["value"] as? String else { return nil }
                return WidgetSettingsField.Option(
                    value: value,
                    label: localizedLabel(
                        key: option["labelKey"] as? String,
                        literal: option["label"] as? String,
                        fallback: value,
                        localize: localize
                    )
                )
            }
        } else {
            options = nil
        }

        return WidgetSettingsField(
            id: id,
            label: label,
            type: type,
            defaultValue: defaultValue,
            options: options
        )
    }

    private static func localizedLabel(
        key: String?,
        literal: String?,
        fallback: String,
        localize: (String) -> String?
    ) -> String {
        if let key, !key.isEmpty, let localized = localize(key), !localized.isEmpty {
            return localized
        }
        if let literal, !literal.isEmpty {
            return literal
        }
        return fallback
    }

    private static func parseDefault(_ raw: Any?, type: WidgetSettingsField.FieldType) -> WidgetSettingValue? {
        guard let raw else { return nil }
        switch type {
        case .text, .select:
            return (raw as? String).map(WidgetSettingValue.string)
        case .number:
            return (raw as? NSNumber).map { .number($0.doubleValue) }
        case .toggle:
            if let bool = raw as? Bool {
                return .bool(bool)
            }
            return (raw as? NSNumber).map { .bool($0.boolValue) }
        }
    }
}

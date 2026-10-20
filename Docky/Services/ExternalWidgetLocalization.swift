//
//  ExternalWidgetLocalization.swift
//  Docky
//

import Foundation

enum ExternalWidgetLocalization {
    static let tableName = "DockyWidget"
    static let displayNameKey = "widget.displayName"

    static func string(
        key: String,
        fallback: String,
        bundle: Bundle,
        languageIdentifier: String
    ) -> String {
        for localization in localizationCandidates(
            languageIdentifier: languageIdentifier,
            availableLocalizations: bundle.localizations
        ) {
            guard let path = bundle.path(forResource: localization, ofType: "lproj"),
                  let localizationBundle = Bundle(path: path) else {
                continue
            }

            let missingValue = "__DOCKY_MISSING_LOCALIZATION__"
            let value = localizationBundle.localizedString(
                forKey: key,
                value: missingValue,
                table: tableName
            )
            if value != missingValue {
                return value
            }
        }

        return fallback
    }

    static func localizationCandidates(
        languageIdentifier: String,
        availableLocalizations: [String]
    ) -> [String] {
        let requested = normalizedIdentifier(languageIdentifier)
        let requestedLanguage = languageCode(for: requested)
        var candidates: [String] = []

        func append(_ candidate: String?) {
            guard let candidate, !candidates.contains(candidate) else {
                return
            }
            candidates.append(candidate)
        }

        append(availableLocalizations.first {
            normalizedIdentifier($0) == requested
        })
        append(availableLocalizations.first {
            languageCode(for: $0) == requestedLanguage
                && normalizedIdentifier($0) == requestedLanguage
        })
        append(availableLocalizations.first {
            languageCode(for: $0) == requestedLanguage
        })
        append(availableLocalizations.first {
            normalizedIdentifier($0) == "en"
        })
        append(availableLocalizations.first {
            languageCode(for: $0) == "en"
        })

        return candidates
    }

    private static func normalizedIdentifier(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func languageCode(for identifier: String) -> String {
        normalizedIdentifier(identifier).split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
    }
}

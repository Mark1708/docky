//
//  FoundationModelLocalePolicy.swift
//  Docky
//

import Foundation

struct FoundationModelLocalePolicy: Equatable {
    let effectiveLanguageIdentifier: String

    init(languageIdentifier: String = AppLocalization.effectiveLanguageIdentifier) {
        effectiveLanguageIdentifier = languageIdentifier
    }

    var effectiveLocale: Locale {
        Locale(identifier: effectiveLanguageIdentifier)
    }

    var englishLanguageName: String {
        let languageCode = effectiveLanguageIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init)
            ?? AppLocalization.fallbackLanguageIdentifier
        return Locale(identifier: "en").localizedString(forLanguageCode: languageCode)
            ?? languageCode
    }

    var responseInstruction: String {
        "Write every user-visible folder title in \(englishLanguageName). Keep app names and the structured values for kind, bundleIdentifier, bundleIdentifiers, widgetKind, widgetOwnerBundleIdentifier, widgetSpan, owner, and all widget raw values exactly as provided. Do not translate or rewrite those structural tokens."
    }
}

import Foundation

enum AppLocalization {
    static let fallbackLanguageIdentifier = "en"

    static func effectiveLanguageIdentifier(
        preferredLanguages: [String],
        availableLocalizations: [String],
        developmentLocalization: String?
    ) -> String {
        let localizations = availableLocalizations.filter { $0 != "Base" }
        if let preferred = Bundle.preferredLocalizations(
            from: localizations,
            forPreferences: preferredLanguages
        ).first {
            return preferred
        }

        if let developmentLocalization,
           localizations.contains(developmentLocalization) {
            return developmentLocalization
        }

        if localizations.contains(fallbackLanguageIdentifier) {
            return fallbackLanguageIdentifier
        }

        return developmentLocalization ?? fallbackLanguageIdentifier
    }

    static var effectiveLanguageIdentifier: String {
        effectiveLanguageIdentifier(
            preferredLanguages: Locale.preferredLanguages,
            availableLocalizations: Bundle.main.localizations,
            developmentLocalization: Bundle.main.developmentLocalization
        )
    }

    static func string(
        key: String,
        fallback: String,
        table: String? = nil,
        bundle: Bundle = .main
    ) -> String {
        bundle.localizedString(forKey: key, value: fallback, table: table)
    }
}

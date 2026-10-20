import Foundation

enum LocalizedNumberInput {
    static func format(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(
            .number
                .locale(locale)
                .grouping(.never)
                .precision(.fractionLength(0...12))
        )
    }

    static func parse(_ text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return try? FloatingPointFormatStyle<Double>
            .number
            .locale(locale)
            .parseStrategy
            .parse(trimmed)
    }
}

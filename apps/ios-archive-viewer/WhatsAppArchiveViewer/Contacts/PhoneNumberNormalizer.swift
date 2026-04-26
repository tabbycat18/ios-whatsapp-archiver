import Foundation

enum PhoneNumberNormalizer {
    enum Source {
        case whatsAppJID
        case contactPhoneNumber
        case archivedPhoneNumber
    }

    static func comparableKey(from value: String?, source: Source, locale: Locale = .current) -> String? {
        guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        switch source {
        case .whatsAppJID:
            return comparableKeyFromWhatsAppJID(rawValue)
        case .contactPhoneNumber:
            return comparableKeyFromContactPhoneNumber(rawValue, locale: locale)
        case .archivedPhoneNumber:
            return comparableKeyFromArchivedPhoneNumber(rawValue, locale: locale)
        }
    }

    static func safeDisplayPhoneNumber(from value: String?) -> String? {
        guard let key = comparableKey(from: value, source: .whatsAppJID) else {
            return nil
        }
        return "+\(key)"
    }

    private static func comparableKeyFromWhatsAppJID(_ value: String) -> String? {
        let lowercasedValue = value.lowercased()
        guard !lowercasedValue.contains("@lid"),
              !lowercasedValue.contains("@g.us"),
              !value.contains(";"),
              !value.contains(","),
              let atIndex = value.firstIndex(of: "@") else {
            return nil
        }

        let localPart = String(value[..<atIndex])
        let domainAndSuffix = String(value[value.index(after: atIndex)...]).lowercased()
        let domain = domainAndSuffix.split(whereSeparator: { $0 == "/" || $0 == ":" }).first.map(String.init)
        guard domain == "s.whatsapp.net" else {
            return nil
        }

        let phoneCandidate = localPart.split(whereSeparator: { $0 == "/" || $0 == ":" }).first.map(String.init) ?? ""
        guard phoneCandidate.allSatisfy(\.isNumber) else {
            return nil
        }
        return validInternationalDigits(phoneCandidate)
    }

    private static func comparableKeyFromArchivedPhoneNumber(_ value: String, locale: Locale) -> String? {
        if value.contains("@") {
            return comparableKeyFromWhatsAppJID(value)
        }
        return comparableKeyFromContactPhoneNumber(value, locale: locale)
    }

    private static func comparableKeyFromContactPhoneNumber(_ value: String, locale: Locale) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !looksOpaque(trimmed) else {
            return nil
        }

        let normalizedPrefix = trimmed.replacingOccurrences(of: "\u{00a0}", with: " ")
        let digits = normalizedPrefix.filter(\.isNumber)
        guard digits.count >= 7, digits.count <= 15 else {
            return nil
        }

        if normalizedPrefix.firstNonWhitespace == "+" {
            return validInternationalDigits(digits)
        }

        if digits.hasPrefix("00") {
            return validInternationalDigits(String(digits.dropFirst(2)))
        }

        if isSwissLocale(locale),
           digits.hasPrefix("0"),
           digits.count == 10 {
            return validInternationalDigits("41" + String(digits.dropFirst()))
        }

        if digits.hasPrefix("41"), digits.count == 11 {
            return validInternationalDigits(digits)
        }

        return nil
    }

    private static func validInternationalDigits(_ digits: some StringProtocol) -> String? {
        let value = String(digits)
        guard value.count >= 7,
              value.count <= 15,
              !value.hasPrefix("0"),
              value.allSatisfy(\.isNumber) else {
            return nil
        }
        return value
    }

    private static func isSwissLocale(_ locale: Locale) -> Bool {
        locale.region?.identifier.uppercased() == "CH"
    }

    private static func looksOpaque(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if lowercased.contains("@lid") || lowercased.contains("@g.us") {
            return true
        }
        if value.contains("@") {
            return true
        }
        if value.range(of: #"^[A-Za-z0-9+/=_-]{12,}$"#, options: .regularExpression) != nil,
           value.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }
}

private extension String {
    var firstNonWhitespace: Character? {
        first { !$0.isWhitespace }
    }
}

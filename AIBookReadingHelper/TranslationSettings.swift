import Foundation

/// Keys for the choices the app remembers between launches.
enum SettingsKey {
    static let engine = "translationEngine"
    static let targetLanguage = "targetLanguage"
    static let googleAPIKey = "googleAPIKey"
}

/// The service that translates the selected text. Chosen from the View menu.
enum TranslationEngine: String, CaseIterable, Identifiable {
    case google
    case apple

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .google: "Google Translation"
        case .apple: "Apple Translation"
        }
    }
}

/// A language the selection can be translated into, with the code each service expects for it.
struct TargetLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    let googleCode: String
    let appleCode: String

    init(_ name: String, google: String, apple: String? = nil) {
        self.id = google
        self.name = name
        self.googleCode = google
        self.appleCode = apple ?? google
    }

    static let all: [TargetLanguage] = [
        TargetLanguage("Arabic", google: "ar"),
        TargetLanguage("Chinese (Simplified)", google: "zh-CN", apple: "zh-Hans"),
        TargetLanguage("Chinese (Traditional)", google: "zh-TW", apple: "zh-Hant"),
        TargetLanguage("Dutch", google: "nl"),
        TargetLanguage("English", google: "en"),
        TargetLanguage("French", google: "fr"),
        TargetLanguage("German", google: "de"),
        TargetLanguage("Hindi", google: "hi"),
        TargetLanguage("Indonesian", google: "id"),
        TargetLanguage("Italian", google: "it"),
        TargetLanguage("Japanese", google: "ja"),
        TargetLanguage("Korean", google: "ko"),
        TargetLanguage("Polish", google: "pl"),
        TargetLanguage("Portuguese (Brazil)", google: "pt", apple: "pt-BR"),
        TargetLanguage("Russian", google: "ru"),
        TargetLanguage("Spanish", google: "es"),
        TargetLanguage("Thai", google: "th"),
        TargetLanguage("Turkish", google: "tr"),
        TargetLanguage("Ukrainian", google: "uk"),
        TargetLanguage("Vietnamese", google: "vi"),
    ]

    static func language(withID id: String) -> TargetLanguage {
        all.first { $0.id == id } ?? all.first { $0.id == "en" }!
    }

    /// The first of the Mac's preferred languages that is in the list, or English.
    static var defaultID: String {
        for preferred in Locale.preferredLanguages {
            if let match = all.first(where: { preferred.hasPrefix($0.appleCode) }) {
                return match.id
            }
        }
        return "en"
    }
}

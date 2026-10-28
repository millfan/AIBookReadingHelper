import Foundation

/// Keys for the choices the app remembers between launches.
enum SettingsKey {
    static let engine = "translationEngine"
    static let direction = "translationDirection"
    static let googleAPIKey = "googleAPIKey"
    static let rotateCamera = "rotateCamera"
    static let leftPaneFraction = "leftPaneFraction"
    static let selectedTextFraction = "selectedTextFraction"
    static let webAddress = "webAddress"
    static let showOpenAI = "showOpenAI"
    static let cameraEnabled = "cameraEnabled"
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

/// A language the selection is translated from or into, with the code each service expects for it.
struct TranslationLanguage: Hashable {
    let name: String
    let googleCode: String
    let appleCode: String

    static let english = TranslationLanguage(name: "English", googleCode: "en", appleCode: "en")
    static let chinese = TranslationLanguage(name: "Chinese", googleCode: "zh-CN", appleCode: "zh-Hans")
}

/// Which way to translate. Chosen from the View menu. Naming the source language means it never has to be detected.
enum TranslationDirection: String, CaseIterable, Identifiable {
    case englishToChinese
    case chineseToEnglish

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .englishToChinese: "ENG → CHN"
        case .chineseToEnglish: "CHN → ENG"
        }
    }

    var source: TranslationLanguage {
        switch self {
        case .englishToChinese: .english
        case .chineseToEnglish: .chinese
        }
    }

    var target: TranslationLanguage {
        switch self {
        case .englishToChinese: .chinese
        case .chineseToEnglish: .english
        }
    }
}

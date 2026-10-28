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
    static let sidePanel = "sidePanel"
    static let documentBookmark = "documentBookmark"
    static let pageZoom = "pageZoom"
    static let cameraEnabled = "cameraEnabled"
}

/// How large the File and Internet views show their pages, changed with Cmd+ and Cmd−. 1 is the normal size.
enum PageZoom {
    static let normal = 1.0
    static let step = 0.1
    static let range = 0.5...3.0

    static func larger(than zoom: Double) -> Double {
        min(((zoom + step) * 10).rounded() / 10, range.upperBound)
    }

    static func smaller(than zoom: Double) -> Double {
        max(((zoom - step) * 10).rounded() / 10, range.lowerBound)
    }
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

/// What the side panel shows. The side panel button steps through them.
enum SidePanel: String {
    /// The selected text, its translation and the dictionary.
    case normal
    case openAI
    case googleTranslate

    var title: String {
        switch self {
        case .normal: "Normal view"
        case .openAI: "OpenAI view"
        case .googleTranslate: "Google Translate"
        }
    }

    var systemImage: String {
        switch self {
        case .normal: "character.book.closed"
        case .openAI: "bubble.left.and.bubble.right"
        case .googleTranslate: "globe"
        }
    }

    /// The panel the button goes to next.
    var next: SidePanel {
        switch self {
        case .normal: .openAI
        case .openAI: .googleTranslate
        case .googleTranslate: .normal
        }
    }
}

import AppKit
import CoreServices

/// Looks words up in the macOS Dictionary.
enum WordDictionary {
    /// Looks the word up in the dictionaries turned on in the Dictionary app.
    static func definition(of word: String) -> String? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        return DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() as String?
    }

    /// The definition laid out as rich text, or a note when the dictionary has no entry.
    static func attributedDefinition(of word: String, fontSize: CGFloat) -> NSAttributedString {
        if let definition = definition(of: word) {
            return DefinitionFormatter.attributedString(for: definition, fontSize: fontSize)
        }
        return NSAttributedString(string: "The dictionary has no entry for “\(word)”. Dictionaries can be added in the Dictionary app's Settings.",
                                  attributes: [.font: NSFont.systemFont(ofSize: fontSize),
                                               .foregroundColor: NSColor.secondaryLabelColor])
    }

    /// The selection as a single word, without the punctuation around it, or nil if it is more than one word.
    static func singleWord(in text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !word.isEmpty, word.count <= 40,
              word.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return word
    }
}

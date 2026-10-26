import CoreServices
import SwiftUI

/// Shows the macOS Dictionary's definition of one word.
struct DictionaryView: View {
    let word: String

    var body: some View {
        if let definition = Self.definition(of: word) {
            ScrollView {
                Text(definition)
                    .font(.system(size: NSFont.systemFontSize * 1.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("The dictionary has no entry for “\(word)”. Dictionaries can be added in the Dictionary app's Settings.")
                .foregroundStyle(.secondary)
        }
    }

    /// Looks the word up in the dictionaries turned on in the Dictionary app.
    static func definition(of word: String) -> String? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        return DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() as String?
    }

    /// The selection as a single word, without the punctuation around it, or nil if it is more than one word.
    static func singleWord(in text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !word.isEmpty, word.count <= 40,
              word.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return word
    }
}

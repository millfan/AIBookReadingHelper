import AppKit
import NaturalLanguage

/// Turns the macOS Dictionary's plain-text definition into laid-out rich text.
/// The Dictionary gives the whole entry as one line; its structure shows only in markers such as
/// "| pronunciation |", the part of speech, sense numbers, "•", and section names in capitals.
enum DefinitionFormatter {
    enum Kind: Equatable {
        /// The headword, with its pronunciation if there is one.
        case headword(pronunciation: String?)
        /// Text before the first part of speech or sense.
        case plain
        /// A part of speech such as "noun", with any word forms that follow it.
        case partOfSpeech
        /// A numbered sense. The number is part of the text for circled Chinese numbers.
        case sense(number: Int?)
        /// A sub-sense marked with "•".
        case subsense
        /// A section such as PHRASES or ORIGIN; the text is its name.
        case section
        /// An entry in PHRASES or PHRASAL VERBS. Its first `nameLength` characters are the phrase itself.
        case phrase(nameLength: Int)
    }

    struct Line: Equatable {
        let kind: Kind
        let text: String
    }

    private static let partsOfSpeech = [
        "noun", "plural noun", "verb", "auxiliary verb", "modal verb", "adjective", "adverb", "pronoun",
        "preposition", "conjunction", "exclamation", "interjection", "determiner", "predeterminer",
        "abbreviation", "prefix", "suffix", "combining form", "symbol", "number", "contraction",
    ]
    private static let sectionNames = ["PHRASAL VERBS", "PHRASES", "DERIVATIVES", "USAGE", "ORIGIN", "NOTE", "SYNONYMS", "ANTONYMS"]
    /// Words that start a definition's object, as in "hoist the sails" or "inform someone".
    private static let objectWords: Set<String> = ["the", "a", "an", "one's", "someone", "something", "someone's"]
    /// Words that belong to phrases, so a definition never starts with them.
    private static let phraseWords: Set<String> = [
        "of", "for", "to", "in", "on", "at", "by", "with", "from", "into", "out", "up", "down", "off", "over",
        "or", "and", "it", "someone", "something", "oneself", "one's", "a", "an", "the",
    ]
    /// Labels that come between a phrase and its definition, as in "run the show informal".
    private static let labelWords = [
        "informal", "archaic", "dated", "formal", "literary", "humorous", "derogatory", "offensive", "rare", "proverb",
        "British", "North", "US", "mainly", "chiefly", "Australian", "Scottish", "Irish", "Canadian",
        "Nautical", "Hunting", "Printing", "Baseball", "Cricket", "Sailing", "Bridge", "Chess", "Grammar", "not",
    ]
    /// Parts of speech in Chinese dictionaries, written after a circled sense number.
    private static let chinesePartsOfSpeech = Set("名动形副量代介连助叹数拟")

    // MARK: - Splitting into lines

    static func lines(of definition: String) -> [Line] {
        let text = definition.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        var lines: [Line] = []
        var bodyStart = 0

        // "apple ap·ple | ˈap(ə)l | noun 1 …": the headword and pronunciation come first.
        // Chinese entries have no pronunciation in pipes; their " | " separates examples after the first sense.
        if let match = firstMatch(#"^([^|①-⑳。]{1,80}?) \| ([^|]{1,80}) \|\s*"#, in: text) {
            // "set 1 | set |": the number tells homographs apart and isn't part of the word.
            let headword = text.substring(with: match.range(at: 1))
                .replacingOccurrences(of: #"\s\d+$"#, with: "", options: .regularExpression)
            lines.append(Line(kind: .headword(pronunciation: text.substring(with: match.range(at: 2))), text: headword))
            bodyStart = match.range.upperBound
        }
        // The word as it appears in phrases, such as "run" in "run away with".
        let stem = lines.first?.text.split(separator: " ").first.map { $0.lowercased() } ?? ""

        enum Break { case partOfSpeech, section, subsense, number(Int), circled, phrase }
        var breaks: [(location: Int, skip: Int, kind: Break)] = []
        let body = NSRange(location: bodyStart, length: text.length - bodyStart)

        let partOfSpeech = partsOfSpeech.joined(separator: "|")
        // A part of speech right at the start of the body, or after a sentence and before sense 1.
        for match in matches("^(?:\(partOfSpeech))\\b", in: text, range: body) {
            breaks.append((match.range.location, 0, .partOfSpeech))
        }
        for match in matches("(?<=[.)\\]]\\s)(?:\(partOfSpeech))(?=\\s(?:(?:\\[[^\\]]*\\]\\s|\\([^)]*\\)\\s)*1\\s|\\[))", in: text, range: body) {
            breaks.append((match.range.location, 0, .partOfSpeech))
        }
        let sections = matches("(?<=\\s)(\(sectionNames.joined(separator: "|")))(?=\\s)", in: text, range: body)
        for (index, match) in sections.enumerated() {
            breaks.append((match.range.location, match.range.length, .section))
            // In PHRASES and PHRASAL VERBS, a phrase starts the section and each sentence that mentions the word.
            let name = text.substring(with: match.range(at: 1))
            guard name == "PHRASES" || name == "PHRASAL VERBS", !stem.isEmpty else { continue }
            let start = match.range.upperBound
            let end = index + 1 < sections.count ? sections[index + 1].range.location : text.length
            breaks.append((start, 0, .phrase))
            // A phrase starts in lowercase, so sense numbers, "•" and capitalized example sentences don't count,
            // and "!" is left out because it ends exclamations inside examples.
            // A note in brackets can run straight into the next phrase: "…cherished]apples and oranges".
            for boundary in matches(#"(?<=[.?])\s+(?=\p{Ll})|(?<=\])(?=\p{Ll})"#, in: text, range: NSRange(location: start, length: end - start)) {
                let after = boundary.range.upperBound
                if boundary.range.location >= 4,
                   text.substring(with: NSRange(location: boundary.range.location - 4, length: 4)) == "etc." {
                    continue
                }
                // The phrase uses the word within its first few words, before any example.
                let opening = text.substring(with: NSRange(location: after, length: min(60, end - after)))
                    .lowercased().prefix { $0 != ":" }
                if opening.split(separator: " ").prefix(7).contains(where: { $0.hasPrefix(stem) }) {
                    breaks.append((after, 0, .phrase))
                }
            }
        }
        for match in matches("\\s*•\\s*", in: text, range: body) {
            breaks.append((match.range.location, match.range.length, .subsense))
        }
        for match in matches("(?<=\\s)(\\d{1,2})\\s(?=[^\\d\\s,.:;])", in: text, range: body) {
            let number = Int(text.substring(with: match.range(at: 1))) ?? 0
            breaks.append((match.range.location, match.range.length, .number(number)))
        }
        for match in matches("[①-⑳]", in: text, range: body) {
            breaks.append((match.range.location, 0, .circled))
        }
        breaks.sort { $0.location < $1.location }

        // Numbers in the text, like "42 marathons", aren't senses. Senses count up from 1 and start again at 1.
        var nextNumber = 1
        var kept: [(location: Int, skip: Int, kind: Kind)] = []
        for item in breaks {
            switch item.kind {
            case .partOfSpeech:
                nextNumber = 1
                kept.append((item.location, item.skip, .partOfSpeech))
            case .section:
                nextNumber = 1
                kept.append((item.location, item.skip, .section))
            case .subsense:
                kept.append((item.location, item.skip, .subsense))
            case .number(let number):
                guard number == nextNumber || number == 1 else { continue }
                nextNumber = number + 1
                kept.append((item.location, item.skip, .sense(number: number)))
            case .circled:
                kept.append((item.location, 0, .sense(number: nil)))
            case .phrase:
                nextNumber = 1
                kept.append((item.location, 0, .phrase(nameLength: 0)))
            }
        }

        func appendText(_ kind: Kind, from start: Int, to end: Int) {
            guard end > start else { return }
            let piece = text.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { return }
            if case .phrase = kind {
                lines.append(Line(kind: .phrase(nameLength: phraseNameLength(in: piece, stem: stem)), text: piece))
            } else {
                lines.append(Line(kind: kind, text: piece))
            }
        }

        // Without a pronunciation, as in Chinese entries, the text before the first sense is the headword.
        var kind: Kind = lines.isEmpty ? .headword(pronunciation: nil) : .plain
        var start = bodyStart
        for item in kept {
            appendText(kind, from: start, to: item.location)
            start = item.location + item.skip
            // A section's name is its own line; what follows it starts as plain text.
            if item.kind == .section {
                lines.append(Line(kind: .section, text: text.substring(with: NSRange(location: item.location, length: item.skip))))
                kind = .plain
            } else {
                kind = item.kind
            }
        }
        appendText(kind, from: start, to: text.length)
        return lines
    }

    /// Where the phrase ends and its definition starts, as in "run away with 1 …", "run the show informal …",
    /// "come running be eager …" or "run across (run across someone) …".
    /// The earliest of these ends it: a bracket, pronunciation, sense number or colon; a label such as "informal";
    /// "!" (kept in the phrase); or, from the third word, a verb that starts the definition.
    private static func phraseNameLength(in text: String, stem: String) -> Int {
        let ns = text as NSString
        let window = NSRange(location: 0, length: min(ns.length, 60))
        var end = ns.length

        // "take it from me I can assure you": a definition can start with "I".
        if let marker = matches(#"\s(?:\(|\[|\||1\s|I\s)|:"#, in: ns, range: window).first {
            end = min(end, marker.range.location)
        }
        let labels = labelWords.joined(separator: "|")
        let label = matches("\\s(?:\(labels))\\b", in: ns, range: window).first
        if let label {
            end = min(end, label.range.location)
        }
        if let exclamation = matches("!", in: ns, range: window).first {
            end = min(end, exclamation.range.upperBound)
        }

        // A pronunciation right after the phrase marks its end for certain: "what goes around comes around | (h)wət … |".
        if let pronunciation = matches(#"\s\|"#, in: ns, range: window).first, pronunciation.range.location == end {
            return (ns.substring(to: end).trimmingCharacters(in: .whitespaces) as NSString).length
        }
        // A label is a surer sign than anything below: "you can't judge a book by its cover proverb …".
        guard label == nil else {
            return (ns.substring(to: end).trimmingCharacters(in: .whitespaces) as NSString).length
        }

        let words = text.split(separator: " ")
        func length(before index: Int) -> Int {
            (words[..<index].joined(separator: " ") as NSString).length
        }
        for index in stride(from: 2, to: min(words.count - 1, 10), by: 1) {
            let word = words[index].lowercased()
            let next = words[index + 1].lowercased()
            let previous = words[index - 1].lowercased()
            // "one for the books an extraordinary feat": the phrase ends with the word, and the definition starts.
            if previous.hasPrefix(stem), ["a", "an"].contains(word) {
                end = min(end, length(before: index))
                break
            }
            guard !word.hasPrefix(stem), !phraseWords.contains(word) || word == words[0].lowercased() else { continue }
            // "set sail hoist the sails": a word followed by "the", "someone" and so on;
            // "by the book strictly according to the rules": an adverb;
            // "in my book in my opinion": the phrase's first word again, once the phrase has used the word.
            if objectWords.contains(next) || (word.hasSuffix("ly") && word.count > 4) || (word == words[0].lowercased() && words[..<index].contains { $0.lowercased().hasPrefix(stem) }) {
                end = min(end, length(before: index))
                break
            }
        }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var index = 0
        var previous = ""
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            let word = text[range].lowercased()
            defer {
                index += 1
                previous = word
            }
            let location = NSRange(range, in: text).location
            guard location < end, index < 10 else { return false }
            // "take it or leave it" and "take it on oneself to do something" keep their own verbs.
            if index >= 2, tag == .verb, !word.hasPrefix(stem), !["to", "or", "and"].contains(previous) {
                end = location
                return false
            }
            return true
        }
        return (ns.substring(to: end).trimmingCharacters(in: .whitespaces) as NSString).length
    }

    // MARK: - Laying out

    static func attributedString(for definition: String, fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let regular = NSFont.systemFont(ofSize: fontSize)
        let bold = NSFont.boldSystemFont(ofSize: fontSize)

        for (index, line) in lines(of: definition).enumerated() {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 2
            var lineText = NSMutableAttributedString()

            switch line.kind {
            case .headword(let pronunciation):
                lineText = NSMutableAttributedString(string: line.text,
                                                     attributes: [.font: NSFont.boldSystemFont(ofSize: fontSize * 1.4),
                                                                  .foregroundColor: NSColor.labelColor])
                if let pronunciation {
                    lineText.append(NSAttributedString(string: "   /\(pronunciation)/",
                                                       attributes: [.font: regular, .foregroundColor: NSColor.secondaryLabelColor]))
                }
                paragraph.paragraphSpacing = 6
            case .plain:
                lineText = body(line.text, font: regular)
            case .partOfSpeech:
                lineText = partOfSpeechLine(line.text, fontSize: fontSize)
                paragraph.paragraphSpacingBefore = index == 0 ? 0 : 8
            case .sense(let number):
                if let number {
                    lineText.append(NSAttributedString(string: "\(number)\t", attributes: [.font: bold, .foregroundColor: NSColor.labelColor]))
                    lineText.append(body(line.text, font: regular))
                } else {
                    lineText = chineseSense(line.text, fontSize: fontSize)
                }
                paragraph.headIndent = fontSize * 1.5
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: fontSize * 1.5)]
                paragraph.paragraphSpacingBefore = 3
            case .subsense:
                lineText.append(NSAttributedString(string: "•\t", attributes: [.font: regular, .foregroundColor: NSColor.secondaryLabelColor]))
                lineText.append(body(line.text, font: regular))
                paragraph.firstLineHeadIndent = fontSize * 1.5
                paragraph.headIndent = fontSize * 2.5
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: fontSize * 2.5)]
            case .phrase(let nameLength):
                lineText = body(line.text, font: regular)
                let name = NSRange(location: 0, length: min(nameLength, lineText.length))
                lineText.addAttributes([.font: bold, .foregroundColor: NSColor.labelColor], range: name)
                paragraph.paragraphSpacingBefore = 6
            case .section:
                lineText = NSMutableAttributedString(string: line.text,
                                                     attributes: [.font: NSFont.boldSystemFont(ofSize: fontSize * 0.8),
                                                                  .foregroundColor: NSColor.secondaryLabelColor,
                                                                  .kern: 1.0])
                paragraph.paragraphSpacingBefore = 12
            }

            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            lineText.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: lineText.length))
            result.append(lineText)
        }
        return result
    }

    /// Body text with its examples (after ":") in italics, and labels such as "[with object]" and
    /// pronunciations "| … |" dimmed.
    private static func body(_ text: String, font: NSFont) -> NSMutableAttributedString {
        let string = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let ns = text as NSString
        // An example runs from a colon to the end of its sentence.
        for match in matches(#"(?<=:\s)[^:]*?(?=\.\s|\.?$)"#, in: ns, range: NSRange(location: 0, length: ns.length)) {
            string.addAttributes([.font: italic(font), .foregroundColor: NSColor.secondaryLabelColor], range: match.range)
        }
        for match in matches(#"\[[^\]]*\]|\|[^|]*\|"#, in: ns, range: NSRange(location: 0, length: ns.length)) {
            string.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
        return string
    }

    /// "verb (runs) (, running …)": the part of speech stands out, the word forms after it are dimmed.
    private static func partOfSpeechLine(_ text: String, fontSize: CGFloat) -> NSMutableAttributedString {
        let string = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize * 0.9),
                                                                          .foregroundColor: NSColor.secondaryLabelColor])
        let ns = text as NSString
        let name = partsOfSpeech.sorted { $0.count > $1.count }.first { ns.hasPrefix($0) } ?? ""
        string.addAttributes([.font: italic(NSFont.boldSystemFont(ofSize: fontSize)), .foregroundColor: NSColor.controlAccentColor],
                             range: NSRange(location: 0, length: (name as NSString).length))
        return string
    }

    /// "①动 写字；记载。书写 | 书法": the number and part of speech stand out, and the examples after "。" are dimmed.
    private static func chineseSense(_ text: String, fontSize: CGFloat) -> NSMutableAttributedString {
        var text = text
        let number = String(text.removeFirst())
        let string = NSMutableAttributedString(string: number + "\t",
                                               attributes: [.font: NSFont.boldSystemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor])
        if let first = text.first, chinesePartsOfSpeech.contains(first) {
            string.append(NSAttributedString(string: String(first) + " ",
                                             attributes: [.font: NSFont.boldSystemFont(ofSize: fontSize), .foregroundColor: NSColor.controlAccentColor]))
            text.removeFirst()
        }
        let rest = text.trimmingCharacters(in: .whitespaces)
        let definition = NSMutableAttributedString(string: rest, attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor])
        if let end = rest.range(of: "。") {
            let location = (String(rest[..<end.upperBound]) as NSString).length
            definition.addAttributes([.font: italic(NSFont.systemFont(ofSize: fontSize)), .foregroundColor: NSColor.secondaryLabelColor],
                                     range: NSRange(location: location, length: (rest as NSString).length - location))
        }
        string.append(definition)
        return string
    }

    private static func italic(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    // MARK: - Regular expressions

    private static func matches(_ pattern: String, in text: NSString, range: NSRange) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        return expression.matches(in: text as String, range: range)
    }

    private static func firstMatch(_ pattern: String, in text: NSString) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        return expression.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length))
    }
}

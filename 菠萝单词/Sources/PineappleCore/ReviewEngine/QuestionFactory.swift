import Foundation

public enum QuestionFactory {
    public static func containsWholeWord(_ text: String, word: String) -> Bool {
        let pattern = "(?i)(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: word) + "(?![A-Za-z])"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
    public static func cloze(_ text: String, answer: String) -> String? {
        let pattern = "(?i)(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: answer) + "(?![A-Za-z])"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard expression.numberOfMatches(in: text, range: range) == 1 else { return nil }
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "___")
    }

    public static func make(word: Vocabulary, pool: [Vocabulary], preferred: QuestionKind,
                            hard: Bool, listeningAvailable: Bool = true) throws -> StudyQuestion {
        let d = word.details
        let example = (d.examples ?? []).compactMap { cloze($0.english, answer: d.word) }.first
        if hard {
            if preferred == .listening && listeningAvailable {
                return StudyQuestion(wordID: word.id, kind: .listening, prompt: "听英式发音，写出单词或词组。", correctAnswer: word.word)
            }
            if let example { return StudyQuestion(wordID: word.id, kind: .cloze, prompt: example, correctAnswer: word.word) }
            if let definition = d.english_definition, !definition.isEmpty,
               !containsWholeWord(definition, word: word.word) || cloze(definition, answer: word.word) != nil {
                return StudyQuestion(wordID: word.id, kind: .definition,
                                     prompt: cloze(definition, answer: word.word) ?? definition, correctAnswer: word.word)
            }
            if listeningAvailable {
                return StudyQuestion(wordID: word.id, kind: .listening, prompt: "听英式发音，写出单词或词组。", correctAnswer: word.word)
            }
        }
        guard !d.coreMeaning.isEmpty else { throw AppError.invalidData("\(word.word) 缺少中文释义，请先补全后练习。") }
        if preferred == .choice && !hard {
            let targetMeanings = Set((d.meanings ?? []).map(TextKey.normalize))
            var seen = targetMeanings
            var distractors: [String] = []
            for candidate in pool.shuffled() where candidate.id != word.id {
                let meaning = candidate.details.coreMeaning
                let meanings = Set((candidate.details.meanings ?? []).map(TextKey.normalize))
                guard !meaning.isEmpty, TextKey.normalize(candidate.word) != TextKey.normalize(word.word),
                      meanings.isDisjoint(with: targetMeanings), !seen.contains(TextKey.normalize(meaning)) else { continue }
                seen.insert(TextKey.normalize(meaning)); distractors.append(meaning)
                if distractors.count == 3 { break }
            }
            if distractors.count == 3 {
                return StudyQuestion(wordID: word.id, kind: .choice, prompt: word.word,
                                     hint: d.ipa, options: (distractors + [d.coreMeaning]).shuffled(), correctAnswer: d.coreMeaning)
            }
        }
        let mask = word.word.enumerated().map { index, character in
            character.isWhitespace ? " " : (index == 0 ? String(character) : "_")
        }.joined(separator: " ")
        let hint = hard ? nil : [d.part_of_speech?.joined(separator: " / ") ?? "", example ?? "", mask]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        return StudyQuestion(wordID: word.id, kind: .spelling, prompt: d.coreMeaning,
                             hint: hint, correctAnswer: word.word)
    }
}

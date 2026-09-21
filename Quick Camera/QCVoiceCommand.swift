import Foundation

/// Detection logic for the spoken snapshot command. Deliberately free of audio and
/// session state so it can be unit tested.
enum QCVoiceCommand {
    /// The spoken word that triggers a snapshot.
    static let triggerWord = "snap"

    /// Live transcription reports the same utterance several times (volatile refinements
    /// followed by the finalized text), all within a couple of seconds. Matches inside
    /// this window are treated as one spoken command.
    static let cooldown: TimeInterval = 3

    /// Whether the transcript contains the trigger as a whole word, so words like
    /// "snapshot" or "snapped" don't fire the command.
    static func containsTrigger(_ transcript: String, trigger: String = triggerWord) -> Bool {
        transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .contains(trigger.lowercased())
    }

    /// Whether a match at `date` is a new command rather than a repeat of the last one.
    static func shouldFire(at date: Date, lastFired: Date?, cooldown: TimeInterval = cooldown)
        -> Bool
    {
        guard let lastFired else { return true }
        return date.timeIntervalSince(lastFired) >= cooldown
    }

    /// Volatile transcription usually hears "snap" before the spoken duration ("snap five"
    /// arrives as "snap", then "snap five"). Duration-bearing matches inside this window
    /// refine the command that just fired instead of being dropped by the cooldown.
    static let refinementWindow: TimeInterval = 1.5

    /// Whether a match at `date` refines the command that fired at `lastFired`.
    static func isRefinement(
        at date: Date, lastFired: Date?, window: TimeInterval = refinementWindow
    ) -> Bool {
        guard let lastFired else { return false }
        let elapsed = date.timeIntervalSince(lastFired)
        return elapsed >= 0 && elapsed <= window
    }

    /// Parses an optional duration in seconds from a transcript following the word "snap".
    /// Examples: "snap 3", "please snap 2", "snap five". Values are clamped to 1...maxSeconds.
    static func parsedDurationSeconds(_ transcript: String, maxSeconds: Int = 5) -> TimeInterval? {
        // Tokenize to alphanumerics so punctuation is ignored
        let tokens = transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard let snapIndex = tokens.firstIndex(of: triggerWord.lowercased()) else { return nil }
        let nextIndex = tokens.index(after: snapIndex)
        guard nextIndex < tokens.endIndex else { return nil }

        let word = tokens[nextIndex]
        // digits
        if let value = Int(word) {
            let clamped = min(max(value, 1), maxSeconds)
            return TimeInterval(clamped)
        }
        // spelled-out numbers (one..five)
        let words: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5
        ]
        if let value = words[word] {
            let clamped = min(max(value, 1), maxSeconds)
            return TimeInterval(clamped)
        }
        return nil
    }
}

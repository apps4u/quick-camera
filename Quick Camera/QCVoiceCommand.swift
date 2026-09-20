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
}

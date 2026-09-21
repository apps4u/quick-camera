import Foundation
import Testing

@testable import Quick_Camera

@Suite("Voice command matching")
struct QCVoiceCommandTests {

    @Test(
        "The trigger word is matched wherever it appears",
        arguments: ["snap", "Snap", "SNAP!", "please snap now", "ok, snap.", "snap snap"])
    func triggerIsMatched(transcript: String) {
        #expect(QCVoiceCommand.containsTrigger(transcript))
    }

    @Test(
        "Words merely containing the trigger do not fire",
        arguments: ["snapshot", "snapped", "unsnap", "snappy picture", ""])
    func partialWordsDoNotMatch(transcript: String) {
        #expect(!QCVoiceCommand.containsTrigger(transcript))
    }

    @Test("The first match always fires")
    func firstMatchFires() {
        #expect(QCVoiceCommand.shouldFire(at: Date(timeIntervalSince1970: 100), lastFired: nil))
    }

    @Test("A repeat inside the cooldown window is the same utterance")
    func repeatWithinCooldownIsSuppressed() {
        let first = Date(timeIntervalSince1970: 100)
        let repeated = first.addingTimeInterval(QCVoiceCommand.cooldown / 2)
        #expect(!QCVoiceCommand.shouldFire(at: repeated, lastFired: first))
    }

    @Test("A match after the cooldown fires again")
    func matchAfterCooldownFires() {
        let first = Date(timeIntervalSince1970: 100)
        let later = first.addingTimeInterval(QCVoiceCommand.cooldown)
        #expect(QCVoiceCommand.shouldFire(at: later, lastFired: first))
    }
}

@Suite("Voice command duration parsing")
struct QCVoiceCommandParsingTests {

    @Test("No number after snap yields nil duration", arguments: [
        "snap",
        "please snap now",
        "ok, snap!",
        "snap for a bit"
    ])
    func noDuration(transcript: String) {
        #expect(QCVoiceCommand.parsedDurationSeconds(transcript) == nil)
    }

    @Test("Digits after snap are parsed and clamped to 1...5", arguments: [
        ("snap 1", 1.0),
        ("snap 3", 3.0),
        ("snap 5", 5.0),
        ("snap 0", 1.0), // clamped up
        ("snap 10", 5.0) // clamped down
    ])
    func numericDuration(transcript: String, expected: TimeInterval) {
        #expect(QCVoiceCommand.parsedDurationSeconds(transcript) == expected)
    }

    @Test("Spelled-out numbers one..five are parsed", arguments: [
        ("snap one", 1.0),
        ("snap two", 2.0),
        ("snap three", 3.0),
        ("snap four", 4.0),
        ("snap five", 5.0)
    ])
    func wordDuration(transcript: String, expected: TimeInterval) {
        #expect(QCVoiceCommand.parsedDurationSeconds(transcript) == expected)
    }
}

@Suite("Voice command refinement window")
struct QCVoiceCommandRefinementTests {

    @Test("A match shortly after the trigger refines it")
    func matchInsideWindowRefines() {
        let fired = Date(timeIntervalSince1970: 100)
        let refined = fired.addingTimeInterval(QCVoiceCommand.refinementWindow / 2)
        #expect(QCVoiceCommand.isRefinement(at: refined, lastFired: fired))
    }

    @Test("A match past the refinement window does not refine")
    func matchOutsideWindowDoesNotRefine() {
        let fired = Date(timeIntervalSince1970: 100)
        let late = fired.addingTimeInterval(QCVoiceCommand.refinementWindow + 0.1)
        #expect(!QCVoiceCommand.isRefinement(at: late, lastFired: fired))
    }

    @Test("Nothing refines before any trigger has fired")
    func noPriorTriggerDoesNotRefine() {
        #expect(!QCVoiceCommand.isRefinement(at: Date(timeIntervalSince1970: 100), lastFired: nil))
    }
}


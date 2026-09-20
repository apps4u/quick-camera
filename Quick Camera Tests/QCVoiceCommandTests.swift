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

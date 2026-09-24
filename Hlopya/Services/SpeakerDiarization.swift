import Foundation
import FluidAudio

/// Per-frame speaker activity from Nemotron 3 Diarization (10 ms frames, up to 8 speakers).
struct SpeakerActivity {
    let probabilities: [Float]  // [frameCount * numSpeakers]
    let frameCount: Int
    let numSpeakers: Int
    let frameSeconds: Double = 0.01

    /// Speaker slot with the most activity over [start, end], or nil if nobody is active.
    func dominantSpeaker(start: Double, end: Double) -> Int? {
        guard frameCount > 0 else { return nil }
        let first = max(0, min(frameCount - 1, Int(start / frameSeconds)))
        let last = max(first, min(frameCount - 1, Int(end / frameSeconds)))
        var sums = [Float](repeating: 0, count: numSpeakers)
        for frame in first...last {
            let base = frame * numSpeakers
            for spk in 0..<numSpeakers {
                sums[spk] += probabilities[base + spk]
            }
        }
        guard let best = sums.indices.max(by: { sums[$0] < sums[$1] }) else { return nil }
        // Mean probability below 0.1 means silence/noise for every slot
        return sums[best] / Float(last - first + 1) >= 0.1 ? best : nil
    }
}

enum SpeakerLabeling {
    /// A word built from ASR tokens, attributed to a diarizer speaker slot.
    struct Word {
        var tokens: [TokenTiming]
        var speaker: Int?
        var start: Double { tokens.first?.startTime ?? 0 }
        var end: Double { tokens.last?.endTime ?? start }
    }

    /// Group subword tokens into words (a token starting with whitespace opens a new word)
    /// and attribute each word to its dominant speaker. Silent words inherit the previous speaker.
    static func words(from timings: [TokenTiming], activity: SpeakerActivity?) -> [Word] {
        var words: [Word] = []
        for timing in timings {
            if words.isEmpty || timing.token.first?.isWhitespace == true {
                words.append(Word(tokens: [timing]))
            } else {
                words[words.count - 1].tokens.append(timing)
            }
        }
        guard let activity else { return words }

        var previous: Int?
        for i in words.indices {
            let speaker = activity.dominantSpeaker(start: words[i].start, end: words[i].end) ?? previous
            words[i].speaker = speaker
            previous = speaker
        }
        // Leading silent words take the first attributed speaker
        if let firstKnown = words.first(where: { $0.speaker != nil })?.speaker {
            for i in words.indices where words[i].speaker == nil { words[i].speaker = firstKnown }
        }
        return words
    }

    /// System track: one voice stays "Them"; several become "Them 1", "Them 2"... in arrival order.
    static func systemLabels(for words: [Word]) -> [Int: String] {
        let order = arrivalOrder(words)
        guard order.count > 1 else { return Dictionary(uniqueKeysWithValues: order.map { ($0, "Them") }) }
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, "Them \($0 + 1)") })
    }

    /// Mic track: the voice with the most talk time is "Me"; other in-room voices are "Room 1", "Room 2"...
    static func micLabels(for words: [Word]) -> [Int: String] {
        var talkTime: [Int: Double] = [:]
        for word in words {
            if let spk = word.speaker { talkTime[spk, default: 0] += max(word.end - word.start, 0) }
        }
        guard let me = talkTime.max(by: { $0.value < $1.value })?.key else { return [:] }
        var labels = [me: "Me"]
        for (n, spk) in arrivalOrder(words).filter({ $0 != me }).enumerated() {
            labels[spk] = "Room \(n + 1)"
        }
        return labels
    }

    private static func arrivalOrder(_ words: [Word]) -> [Int] {
        var seen: [Int] = []
        for word in words {
            if let spk = word.speaker, !seen.contains(spk) { seen.append(spk) }
        }
        return seen
    }
}

import Foundation

/// Compile together with the production PlaybackQueue.swift; this file does not
/// copy the queue implementation, require an app install, or touch UserDefaults.
@main
struct PlaybackQueueRegression {
    struct TestFailure: Error {
        let message: String
    }

    struct Result: Codable {
        let name: String
        let passed: Bool
        let assertions: Int
        let failure: String?
    }

    struct Report: Codable {
        let scope: String
        let passed: Int
        let total: Int
        let assertions: Int
        let results: [Result]
    }

    final class Check {
        private(set) var assertions = 0

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            assertions += 1
            guard condition() else { throw TestFailure(message: message) }
        }

        func permutation(_ actual: [UUID], of expected: [UUID], _ message: String) throws {
            try expect(actual.count == expected.count && Set(actual) == Set(expected), message)
            try expect(Set(actual).count == actual.count, "\(message): no duplicate candidates")
        }
    }

    static func main() throws {
        let cases: [(String, (Check) throws -> Void)] = [
            ("sequential navigation and library boundaries", sequentialNavigation),
            ("finite playlist repeat in both directions", repeatNavigation),
            ("empty queue and unknown track", emptyAndUnknown),
            ("single-track queue", singleTrack),
            ("shuffle anchors selected track and preserves source order", shuffleAnchor),
            ("shuffle next then previous retraces the stable queue", shuffleBacktracking),
            ("shuffle survives playlist reorder and adds new tracks once", shuffleReconcile),
            ("shuffle removes deleted tracks including current track", shuffleDeletion),
            ("switching playlists cannot retain old candidates", playlistSwitch),
            ("disabling shuffle restores saved order", disableShuffle),
            ("explicit shuffle restart anchors newly selected track", restartShuffle),
            ("single mode button cycles playlist, shuffle, one, off", playbackModeCycle),
            ("bounded fallback visits every track at most once", boundedFallback),
            ("randomized shuffle invariants across queue sizes", randomizedInvariants)
        ]
        var results: [Result] = []
        for (name, test) in cases {
            let check = Check()
            do {
                try test(check)
                results.append(Result(name: name, passed: true, assertions: check.assertions, failure: nil))
                print("PASS: \(name) [\(check.assertions) assertions]")
            } catch let error as TestFailure {
                results.append(Result(name: name, passed: false, assertions: check.assertions, failure: error.message))
                print("FAIL: \(name): \(error.message)")
            } catch {
                results.append(Result(name: name, passed: false, assertions: check.assertions, failure: "Unexpected test error"))
                print("FAIL: \(name): unexpected test error")
            }
        }
        let passed = results.filter(\.passed).count
        let assertions = results.reduce(0) { $0 + $1.assertions }
        let report = Report(
            scope: "Production PlaybackQueue and PlaybackMode; no audio engine or UI execution",
            passed: passed, total: results.count, assertions: assertions, results: results
        )
        if CommandLine.arguments.count == 2 {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
        }
        print("RESULT: passed / total = \(passed) / \(results.count); assertions = \(assertions)")
        guard passed == results.count else { throw TestFailure(message: "Regression failure") }
    }

    static func sequentialNavigation(_ check: Check) throws {
        let ids = (0..<4).map { _ in UUID() }
        var queue = PlaybackQueue()
        queue.update(trackIDs: ids, currentID: ids[1], shuffle: false)
        try check.expect(queue.orderedIDs == ids, "Normal mode must retain saved order")
        try check.expect(queue.candidates(after: ids[0], direction: .previous, wrap: false).isEmpty, "No previous track before library start")
        try check.expect(queue.candidates(after: ids[3], direction: .next, wrap: false).isEmpty, "No next track after library end")
        try check.expect(queue.candidates(after: ids[1], direction: .next, wrap: false) == [ids[2], ids[3]], "Next starts with the next track and can skip later unavailable files")
        try check.expect(queue.candidates(after: ids[2], direction: .previous, wrap: false) == [ids[1], ids[0]], "Previous walks backwards through saved order")
        try check.expect(queue.candidates(startingAt: ids[2], direction: .next, wrap: false) == [ids[2], ids[3]], "Explicit selection begins with the selected track")
        try check.expect(queue.candidates(startingAt: ids[1], direction: .previous, wrap: false) == [ids[1], ids[0]], "Backward fallback begins with the requested track")
    }

    static func repeatNavigation(_ check: Check) throws {
        let ids = (0..<4).map { _ in UUID() }
        var queue = PlaybackQueue()
        queue.update(trackIDs: ids, currentID: ids[3], shuffle: false)
        try check.expect(queue.candidates(after: ids[3], direction: .next, wrap: true) == ids, "Repeat advances from the last track to the first")
        try check.expect(queue.candidates(after: ids[0], direction: .previous, wrap: true) == ids.reversed(), "Repeat moves from the first track to the last")
        try check.expect(queue.candidates(startingAt: ids[2], direction: .next, wrap: true) == [ids[2], ids[3], ids[0], ids[1]], "Selection fallback can traverse the playlist boundary once")
        try check.expect(queue.candidates(startingAt: ids[1], direction: .previous, wrap: true) == [ids[1], ids[0], ids[3], ids[2]], "Backward fallback can traverse the playlist boundary once")
        for id in ids {
            try check.permutation(queue.candidates(after: id, direction: .next, wrap: true), of: ids, "Forward fallback is one finite pass")
            try check.permutation(queue.candidates(after: id, direction: .previous, wrap: true), of: ids, "Backward fallback is one finite pass")
        }
    }

    static func emptyAndUnknown(_ check: Check) throws {
        let missing = UUID()
        var queue = PlaybackQueue()
        for shuffle in [false, true] {
            queue.update(trackIDs: [], currentID: missing, shuffle: shuffle)
            try check.expect(queue.orderedIDs.isEmpty, "An empty library cannot contain a missing selected track")
            for direction in [PlaybackQueue.Direction.previous, .next] {
                for wrap in [false, true] {
                    try check.expect(queue.candidates(after: missing, direction: direction, wrap: wrap).isEmpty, "Empty navigation yields no candidate")
                    try check.expect(queue.candidates(startingAt: missing, direction: direction, wrap: wrap).isEmpty, "Missing selection yields no candidate")
                }
            }
        }
        let ids = [UUID(), UUID()]
        queue.update(trackIDs: ids, currentID: missing, shuffle: true)
        try check.permutation(queue.orderedIDs, of: ids, "Shuffle cannot insert an unknown current ID")
        try check.expect(queue.candidates(after: missing, direction: .next, wrap: true).isEmpty, "Unknown current ID cannot wrap into the library")
    }

    static func singleTrack(_ check: Check) throws {
        let id = UUID()
        var queue = PlaybackQueue()
        for shuffle in [false, true] {
            queue.update(trackIDs: [id], currentID: id, shuffle: shuffle)
            try check.expect(queue.orderedIDs == [id], "Singleton shuffle remains a singleton")
            for direction in [PlaybackQueue.Direction.previous, .next] {
                try check.expect(queue.candidates(after: id, direction: direction, wrap: false).isEmpty, "Singleton has no adjacent track without repeat")
                try check.expect(queue.candidates(after: id, direction: direction, wrap: true) == [id], "Singleton repeats itself exactly once per request")
                try check.expect(queue.candidates(startingAt: id, direction: direction, wrap: true) == [id], "Singleton error fallback is finite")
            }
        }
    }

    static func shuffleAnchor(_ check: Check) throws {
        let savedOrder = (0..<12).map { _ in UUID() }
        let inputCopy = savedOrder
        let selected = savedOrder[7]
        var queue = PlaybackQueue()
        queue.update(trackIDs: savedOrder, currentID: selected, shuffle: true)
        try check.expect(queue.orderedIDs.first == selected, "Enabling shuffle must keep the selected track first")
        try check.permutation(queue.orderedIDs, of: savedOrder, "Shuffle visits each selected-playlist track once")
        try check.expect(savedOrder == inputCopy, "Shuffle must not change saved playlist ordering")
        try check.expect(queue.candidates(after: selected, direction: .previous, wrap: false).isEmpty, "No invented previous history on enabling shuffle")
        try check.permutation(queue.candidates(after: selected, direction: .next, wrap: false), of: savedOrder.filter { $0 != selected }, "Every remaining track is eligible once")
    }

    static func shuffleBacktracking(_ check: Check) throws {
        let ids = (0..<10).map { _ in UUID() }
        var queue = PlaybackQueue()
        queue.update(trackIDs: ids, currentID: ids[4], shuffle: true)
        let originalQueue = queue.orderedIDs
        for index in 0..<(originalQueue.count - 1) {
            let current = originalQueue[index]
            guard let next = queue.candidates(after: current, direction: .next, wrap: false).first else {
                throw TestFailure(message: "Shuffle lost the next track before reaching the end")
            }
            queue.update(trackIDs: ids, currentID: next, shuffle: true)
            try check.expect(queue.candidates(after: next, direction: .previous, wrap: false).first == current, "Previous must retrace the preceding shuffled track")
            try check.expect(queue.orderedIDs == originalQueue, "Refreshing transport state cannot reshuffle the queue")
        }
        try check.expect(queue.candidates(after: originalQueue[9], direction: .next, wrap: false).isEmpty, "Shuffle without repeat stops after a complete pass")
    }

    static func shuffleReconcile(_ check: Check) throws {
        let ids = (0..<6).map { _ in UUID() }
        let additions = [UUID(), UUID()]
        var queue = PlaybackQueue()
        queue.update(trackIDs: ids, currentID: ids[2], shuffle: true)
        let originalQueue = queue.orderedIDs
        queue.update(trackIDs: ids.reversed(), currentID: ids[2], shuffle: true)
        try check.expect(queue.orderedIDs == originalQueue, "Reordering a playlist must not discard shuffle playback history")
        queue.update(trackIDs: ids + additions, currentID: ids[2], shuffle: true)
        try check.expect(Array(queue.orderedIDs.prefix(ids.count)) == originalQueue, "Importing tracks preserves the active queue prefix")
        try check.permutation(Array(queue.orderedIDs.suffix(additions.count)), of: additions, "New tracks are appended once")
        let expandedQueue = queue.orderedIDs
        queue.update(trackIDs: ids + additions, currentID: ids[2], shuffle: true)
        try check.expect(queue.orderedIDs == expandedQueue, "Repeated refresh cannot duplicate imported tracks")
    }

    static func shuffleDeletion(_ check: Check) throws {
        let ids = (0..<8).map { _ in UUID() }
        var queue = PlaybackQueue()
        queue.update(trackIDs: ids, currentID: ids[2], shuffle: true)
        let beforeDeletion = queue.orderedIDs
        let removed = Set([ids[2], ids[5]])
        let remaining = ids.filter { !removed.contains($0) }
        queue.update(trackIDs: remaining, currentID: ids[2], shuffle: true)
        try check.expect(queue.orderedIDs == beforeDeletion.filter { !removed.contains($0) }, "Deleting tracks removes only those entries from stable shuffle order")
        try check.expect(queue.candidates(after: ids[2], direction: .next, wrap: true).isEmpty, "Deleted selected track cannot navigate stale history")
        try check.permutation(queue.orderedIDs, of: remaining, "Remaining queue contains only live tracks")
        queue.update(trackIDs: [], currentID: nil, shuffle: true)
        try check.expect(queue.orderedIDs.isEmpty, "Deleting every track empties the shuffled queue")
    }

    static func playlistSwitch(_ check: Check) throws {
        let firstPlaylist = (0..<4).map { _ in UUID() }
        let secondPlaylist = (0..<5).map { _ in UUID() }
        var queue = PlaybackQueue()
        queue.update(trackIDs: firstPlaylist, currentID: firstPlaylist[0], shuffle: true)
        queue.update(trackIDs: secondPlaylist, currentID: secondPlaylist[3], shuffle: true, restart: true)
        try check.expect(queue.orderedIDs.first == secondPlaylist[3], "Explicit selection in another playlist starts there")
        try check.permutation(queue.orderedIDs, of: secondPlaylist, "The new playlist is the entire playback scope")
        try check.expect(Set(queue.orderedIDs).isDisjoint(with: firstPlaylist), "No old playlist track leaks into a new queue")
    }

    static func disableShuffle(_ check: Check) throws {
        let ids = (0..<8).map { _ in UUID() }
        var queue = PlaybackQueue()
        queue.update(trackIDs: ids, currentID: ids[3], shuffle: true)
        queue.update(trackIDs: ids, currentID: ids[3], shuffle: false)
        try check.expect(queue.orderedIDs == ids, "Disabling shuffle restores saved track order")
        try check.expect(queue.candidates(after: ids[3], direction: .next, wrap: false).first == ids[4], "Next now follows saved playlist order")
        queue.update(trackIDs: ids, currentID: ids[5], shuffle: true)
        try check.expect(queue.orderedIDs.first == ids[5], "Re-enabling shuffle anchors the current track, not an old selection")
        try check.permutation(queue.orderedIDs, of: ids, "A new shuffle still contains each track exactly once")
    }

    static func restartShuffle(_ check: Check) throws {
        let ids = (0..<7).map { _ in UUID() }
        var queue = PlaybackQueue()
        queue.update(trackIDs: ids, currentID: ids[0], shuffle: true)
        queue.update(trackIDs: ids, currentID: ids[4], shuffle: true, restart: true)
        try check.expect(queue.orderedIDs.first == ids[4], "Explicit track selection starts a fresh shuffle from that track")
        try check.permutation(queue.candidates(startingAt: ids[4], direction: .next, wrap: false), of: ids, "All playlist tracks remain reachable after selection")
        queue.update(trackIDs: ids, currentID: nil, shuffle: true, restart: true)
        try check.permutation(queue.orderedIDs, of: ids, "Shuffle without a selected track still includes the whole playlist")
    }

    static func playbackModeCycle(_ check: Check) throws {
        let expectedModes: Set<PlaybackMode> = [.off, .repeatPlaylist, .shuffle, .repeatOne]
        try check.expect(Set(PlaybackMode.allCases) == expectedModes, "The button must expose exactly four mutually exclusive states")
        var mode = PlaybackMode.off
        for expected in [PlaybackMode.repeatPlaylist, .shuffle, .repeatOne, .off, .repeatPlaylist, .shuffle, .repeatOne, .off] {
            mode = mode.next
            try check.expect(mode == expected, "Mode control must follow playlist → shuffle → one → off")
            try check.expect(PlaybackMode(rawValue: mode.rawValue) == mode, "A saved mode preference must decode to the same exclusive state")
            try check.expect(!mode.title.isEmpty, "Every mode needs an accessibility description")
            try check.expect(!mode.symbol.isEmpty, "Every mode needs a visible symbol")
        }
        try check.expect(PlaybackMode(rawValue: "invalid-preference") == nil, "Invalid saved state must be detectable for fallback")
        try check.expect(PlaybackMode(rawValue: "shuffle+repeatPlaylist") == nil, "Combined shuffle and repeat must not be a representable saved mode")
    }

    static func boundedFallback(_ check: Check) throws {
        let ids = (0..<16).map { _ in UUID() }
        var queue = PlaybackQueue()
        for shuffle in [false, true] {
            queue.update(trackIDs: ids, currentID: ids[6], shuffle: shuffle, restart: true)
            for id in ids {
                for direction in [PlaybackQueue.Direction.previous, .next] {
                    let candidates = queue.candidates(after: id, direction: direction, wrap: true)
                    try check.permutation(candidates, of: ids, "Every unavailable track is attempted at most once per repeat request")
                    let unavailable = Set(ids)
                    let playable = candidates.first { !unavailable.contains($0) }
                    try check.expect(playable == nil, "An all-unavailable playlist exhausts its finite fallback list")
                    let available = candidates[candidates.count / 2]
                    try check.expect(candidates.first { $0 == available } == available, "Fallback can find an available track after failed candidates")
                }
            }
        }
    }

    static func randomizedInvariants(_ check: Check) throws {
        // Exact random permutations are deliberately not asserted. Repeated fresh
        // queues check membership, bounded traversal and reversible navigation.
        for size in 1...32 {
            let ids = (0..<size).map { _ in UUID() }
            for selected in ids {
                var queue = PlaybackQueue()
                queue.update(trackIDs: ids, currentID: selected, shuffle: true)
                try check.expect(queue.orderedIDs.first == selected, "Shuffle anchor must hold for every selected position")
                try check.permutation(queue.orderedIDs, of: ids, "Shuffle must be a permutation for every tested size")
                let order = queue.orderedIDs
                for current in order {
                    let next = queue.candidates(after: current, direction: .next, wrap: true)
                    try check.permutation(next, of: ids, "Wrapped shuffled traversal has one occurrence of every track")
                    guard let nextID = next.first else { throw TestFailure(message: "Nonempty repeat queue has no next track") }
                    try check.expect(queue.candidates(after: nextID, direction: .previous, wrap: true).first == current, "Previous reverses next, including the cycle boundary")
                }
                queue.update(trackIDs: ids, currentID: selected, shuffle: true)
                try check.expect(queue.orderedIDs == order, "Read/refresh operations preserve shuffle order")
            }
        }
    }
}

import Foundation

enum PlaybackMode: String, CaseIterable {
    case off
    case repeatPlaylist
    case shuffle
    case repeatOne

    var next: Self {
        switch self {
        case .off: .repeatPlaylist
        case .repeatPlaylist: .shuffle
        case .shuffle: .repeatOne
        case .repeatOne: .off
        }
    }

    var title: String {
        switch self {
        case .off: "Обычный порядок"
        case .repeatPlaylist: "Повтор плейлиста"
        case .shuffle: "Случайный порядок"
        case .repeatOne: "Повтор одного трека"
        }
    }

    var symbol: String {
        switch self {
        case .off: "arrow.right"
        case .repeatPlaylist: "repeat"
        case .shuffle: "shuffle"
        case .repeatOne: "repeat.1"
        }
    }
}

/// A stable playback order, separate from the user's saved playlist order.
/// Candidate lists are finite even when repeating: unreadable files cannot loop forever.
struct PlaybackQueue {
    enum Direction {
        case previous
        case next
    }

    private(set) var orderedIDs: [UUID] = []
    private var isShuffled = false

    mutating func update(
        trackIDs: [UUID],
        currentID: UUID?,
        shuffle: Bool,
        restart: Bool = false
    ) {
        if !shuffle {
            orderedIDs = trackIDs
        } else if restart || !isShuffled || orderedIDs.isEmpty {
            let remaining = trackIDs.filter { $0 != currentID }.shuffled()
            orderedIDs = currentID.flatMap { trackIDs.contains($0) ? [$0] : nil } ?? []
            orderedIDs += remaining
        } else {
            let available = Set(trackIDs)
            orderedIDs.removeAll { !available.contains($0) }
            let existing = Set(orderedIDs)
            orderedIDs += trackIDs.filter { !existing.contains($0) }.shuffled()
        }
        isShuffled = shuffle
    }

    func candidates(startingAt id: UUID, direction: Direction, wrap: Bool) -> [UUID] {
        guard let index = orderedIDs.firstIndex(of: id) else { return [] }
        switch direction {
        case .next:
            return Array(orderedIDs[index...]) + (wrap ? Array(orderedIDs[..<index]) : [])
        case .previous:
            return Array(orderedIDs[...index].reversed())
                + (wrap ? Array(orderedIDs[(index + 1)...].reversed()) : [])
        }
    }

    func candidates(after id: UUID, direction: Direction, wrap: Bool) -> [UUID] {
        guard let index = orderedIDs.firstIndex(of: id) else { return [] }
        switch direction {
        case .next:
            return Array(orderedIDs[(index + 1)...])
                + (wrap ? Array(orderedIDs[...index]) : [])
        case .previous:
            return Array(orderedIDs[..<index].reversed())
                + (wrap ? Array(orderedIDs[index...].reversed()) : [])
        }
    }
}

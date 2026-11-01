import Foundation

@MainActor
public protocol PlaylistStoring: AnyObject {
    func fetchSections() throws -> [Playlist]
    func createSection(name: String) throws -> Playlist
    func removeSection(_ section: Playlist) throws
    func renameSection(_ section: Playlist, to name: String) throws
    func setSectionOrder(_ sectionIDs: [UUID]) throws
    func ensureDefaultSection() throws -> Playlist
    func sortedTracks(in section: Playlist) -> [PlaylistTrack]
    func appendTrack(
        title: String,
        artist: String,
        url: URL,
        bookmark: Data,
        duration: Double,
        artwork: Data?,
        to section: Playlist
    ) throws -> PlaylistTrack
    func setCorrupted(_ isCorrupted: Bool, for track: PlaylistTrack) throws
    func updateBookmark(for track: PlaylistTrack, bookmark: Data, url: URL) throws
    func removeTrack(_ track: PlaylistTrack) throws
    func removeTracks(withIDs trackIDs: Set<UUID>, from section: Playlist) throws
    func setTrackOrder(_ trackIDs: [UUID], in section: Playlist) throws
}

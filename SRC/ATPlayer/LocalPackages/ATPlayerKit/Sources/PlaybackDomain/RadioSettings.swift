import Foundation

/// Radio noise maximum and floor; transport and processing failures are separate.
public struct RadioSettings: Equatable, Sendable, Codable {
    public let effectIntensity: Int
    public let backgroundIntensity: Int

    public var isEffectActive: Bool { effectIntensity > 0 }
    public var isBypassed: Bool { !isEffectActive }

    public init(effectIntensity: Int = 0, backgroundIntensity: Int? = nil) {
        let effect = max(0, min(10, effectIntensity))
        let background = max(0, min(10, backgroundIntensity ?? effect))
        self.effectIntensity = max(effect, background)
        self.backgroundIntensity = background
    }

    private enum CodingKeys: String, CodingKey {
        case effectIntensity, backgroundIntensity
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Old station-search/profile keys have no playback effect. A missing
        // floor migrates to the current level, avoiding unexpected silent gaps.
        self.init(
            effectIntensity: (try? values.decode(Int.self, forKey: .effectIntensity)) ?? 0,
            backgroundIntensity: try? values.decode(Int.self, forKey: .backgroundIntensity)
        )
    }
}

public enum RadioPhase: String, Equatable, Sendable {
    case bypassed
    case receiving
    case interference
}

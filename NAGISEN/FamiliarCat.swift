import Foundation

/// Kuro's growth stage and mood, shared by the 3D model, the dojo and the Dashboard card.
enum FamiliarCat {
    enum Stage: Int, CaseIterable, Comparable {
        case kitten, young, grown, elder

        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    enum Mood { case bright, calm, resting }

    static func describe(_ stage: Stage, _ mood: Mood) -> String {
        let who = switch stage {
        case .kitten: String(localized: "A kitten")
        case .young: String(localized: "A young cat")
        case .grown: String(localized: "A grown cat")
        case .elder: String(localized: "An elder cat")
        }
        let how = switch mood {
        case .bright: String(localized: "bright and awake")
        case .calm: String(localized: "calm")
        case .resting: String(localized: "asleep")
        }
        return "\(who), \(how)"
    }
}

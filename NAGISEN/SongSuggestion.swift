import CoreImage
import UIKit
import Vision

/// Picks the card track that fits a photo and the kind of card. Everything runs on this iPhone:
/// Apple's built-in image labels say what is in the photo, its average colour says the mood.
enum SongSuggestion {
    /// What a photo looks like: Vision labels with their confidence, brightness (0…1) and warmth (red minus blue, -1…1).
    struct Look: Equatable {
        var labels: [String: Float] = [:]
        var brightness: Double = 0.5
        var warmth: Double = 0
    }

    /// Vision label names (all from VNClassifyImageRequest) and the tracks each kind of scene points to, best first.
    static let scenes: [(labels: [String], tracks: [CardMusic])] = [
        (["sport", "boxing", "kickboxing", "dumbbell", "barbell", "treadmill", "sports_equipment", "athletics", "gymnastics",
          "cycling", "bicycle", "stadium", "swimming", "ballgames", "football", "basketball"], [.run, .pulse, .steps]),
        (["night_sky", "fireworks", "candle", "sparkler", "nightclub", "concert", "lightning", "spotlight"], [.night, .lantern]),
        (["sunset_sunrise", "sun"], [.sunrise, .dusk]),
        (["blue_sky", "rainbow"], [.sunrise]),
        (["food", "fruit", "vegetable", "bread", "dessert", "coffee", "drink", "salad", "soup", "meat", "rice", "pizza",
          "cake", "tea_drink", "steak", "sushi"], [.ember, .dusk]),
        (["desert", "sand", "camel", "palm_tree", "arch", "ruins", "monument", "castle"], [.atlas]),
        (["water", "water_body", "ocean", "lake", "river", "waterfall", "beach", "shore", "pool", "wetland", "storm", "cloudy"],
         [.tide, .rain]),
        (["forest", "tree", "garden", "plant", "foliage", "flower", "grass", "park", "jungle", "mountain", "hiking", "trail", "path"],
         [.rain, .tide, .steps]),
        (["yoga", "bedroom", "interior_room", "living_room"], [.breath, .still]),
        // No rule for people: they are in most photos, so they would drown out the scene around them.
        (["cityscape", "skyscraper", "street", "road", "building"], [.steps, .pulse]),
    ]

    /// The best track: what the photo shows counts most, then the kind of card, then the photo's mood.
    static func suggest(_ look: Look, theme: Quote.Theme) -> CardMusic {
        var points: [CardMusic: Double] = [:]
        for scene in scenes {
            let seen = Double(scene.labels.compactMap { look.labels[$0] }.max() ?? 0)
            guard seen >= 0.2 else { continue }
            for (rank, track) in scene.tracks.enumerated() { points[track, default: 0] += seen * (1 - 0.2 * Double(rank)) }
        }
        let fits: [CardMusic: Double] = switch theme {
        case .strength, .move: [.run: 0.5, .pulse: 0.45, .steps: 0.4]
        case .streak, .trophy: [.sunrise: 0.4, .pulse: 0.35]
        case .weight: [.steps: 0.35, .breath: 0.3]
        case .day, .any: [.still: 0.3, .dusk: 0.25, .ember: 0.2]
        }
        points.merge(fits, uniquingKeysWith: +)
        if look.brightness < 0.3 { points[.night, default: 0] += 0.3; points[.lantern, default: 0] += 0.2 }
        if look.brightness > 0.65 && look.warmth > 0.1 { points[.sunrise, default: 0] += 0.3 }
        if look.warmth > 0.1 { points[.ember, default: 0] += 0.15; points[.atlas, default: 0] += 0.1 }
        if look.warmth < -0.1 { points[.tide, default: 0] += 0.2; points[.rain, default: 0] += 0.15 }
        // Ties go to the track listed first, so the same photo always gets the same answer.
        return CardMusic.allCases.max { (points[$0] ?? 0) < (points[$1] ?? 0) } ?? .still
    }

    /// Reads a photo off the main thread. When Vision can't run, the labels stay empty and the mood still counts.
    static func look(at photo: UIImage) async -> Look {
        guard let picture = photo.cgImage else { return Look() }
        let orientation = CGImagePropertyOrientation(photo.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            var look = Look()
            let request = VNClassifyImageRequest()
            if (try? VNImageRequestHandler(cgImage: picture, orientation: orientation).perform([request])) != nil {
                for observation in request.results ?? [] where observation.confidence > 0.1 {
                    look.labels[observation.identifier] = observation.confidence
                }
            }
            let image = CIImage(cgImage: picture)
            var pixel = [UInt8](repeating: 0, count: 4)
            if let average = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image,
                                                                          kCIInputExtentKey: CIVector(cgRect: image.extent)])?.outputImage {
                CIContext().render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                let (r, g, b) = (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
                look.brightness = 0.299 * r + 0.587 * g + 0.114 * b
                look.warmth = r - b
            }
            return look
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

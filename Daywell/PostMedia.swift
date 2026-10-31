import AVFoundation
import CoreTransferable
import UIKit
import UniformTypeIdentifiers

enum PostMediaError: LocalizedError, Equatable {
    case unreadable
    case videoTooLong(seconds: Int)
    case tooLarge
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: "That photo or video couldn't be opened."
        case .videoTooLong(let seconds): "Videos can be up to \(Int(PostMedia.maxVideoSeconds)) seconds. This one is \(seconds)."
        case .tooLarge: "That file is over 50 MB, even after compressing it."
        case .exportFailed: "The video couldn't be prepared. Try a different one."
        }
    }
}

/// Turns a picked photo or video into a file small enough to post.
enum PostMedia {
    static let maxVideoSeconds: Double = 60
    static let maxBytes = 50 * 1024 * 1024
    static let maxPhotoEdge: CGFloat = 2048

    /// The size a photo is drawn at: unchanged when it already fits, otherwise scaled so
    /// its longer edge is `maxEdge`.
    static func scaledSize(_ size: CGSize, maxEdge: CGFloat = maxPhotoEdge) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return size }
        let ratio = maxEdge / longest
        return CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
    }

    static func checkSize(_ bytes: Int) throws {
        if bytes > maxBytes { throw PostMediaError.tooLarge }
    }

    static func checkDuration(_ seconds: Double) throws {
        // Half a second of slack for clips trimmed to exactly a minute.
        if seconds > maxVideoSeconds + 0.5 { throw PostMediaError.videoTooLong(seconds: Int(seconds.rounded())) }
    }

    static func photo(from data: Data) throws -> PostAttachment {
        guard let image = UIImage(data: data) else { throw PostMediaError.unreadable }
        let size = scaledSize(image.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { throw PostMediaError.unreadable }
        try checkSize(jpeg.count)
        let url = temporaryURL(extension: "jpg")
        try jpeg.write(to: url)
        return PostAttachment(kind: .photo, fileURL: url)
    }

    static let avatarSide: CGFloat = 512

    /// The centered square to cut from a photo for a profile picture.
    static func centerSquare(of size: CGSize) -> CGRect {
        let side = min(size.width, size.height)
        return CGRect(x: ((size.width - side) / 2).rounded(), y: ((size.height - side) / 2).rounded(),
                      width: side, height: side)
    }

    /// A profile picture: the photo's centered square, 512 px, JPEG.
    static func avatar(from data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw PostMediaError.unreadable }
        let square = centerSquare(of: image.size)
        let side = min(avatarSide, square.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scale = side / square.width
        let output = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: -square.minX * scale, y: -square.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        guard let jpeg = output.jpegData(compressionQuality: 0.85) else { throw PostMediaError.unreadable }
        return jpeg
    }

    static func video(at source: URL) async throws -> PostAttachment {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite else { throw PostMediaError.unreadable }
        try checkDuration(duration)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw PostMediaError.exportFailed
        }
        session.shouldOptimizeForNetworkUse = true
        let output = temporaryURL(extension: "mp4")
        if #available(iOS 18.0, *) {
            do { try await session.export(to: output, as: .mp4) } catch { throw PostMediaError.exportFailed }
        } else {
            session.outputURL = output
            session.outputFileType = .mp4
            await session.export()
            guard session.status == .completed else { throw PostMediaError.exportFailed }
        }
        let bytes = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        try checkSize(bytes)
        return PostAttachment(kind: .video, fileURL: output, posterURL: await posterFrame(for: output))
    }

    /// The video's first frame as a JPEG (up to 1080 px), for grids and story circles.
    static func posterFrame(for video: URL) async -> URL? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1080)
        guard let frame = try? await generator.image(at: .zero).image,
              let jpeg = UIImage(cgImage: frame).jpegData(compressionQuality: 0.8) else { return nil }
        let url = temporaryURL(extension: "jpg")
        return (try? jpeg.write(to: url)) != nil ? url : nil
    }

    /// Width ÷ height a post's media is shown at: its own shape, but never taller than 4:5
    /// or wider than 1.91:1, so one post never takes over the screen.
    static func feedAspectRatio(width: CGFloat, height: CGFloat) -> CGFloat {
        guard width > 0, height > 0 else { return 4.0 / 5.0 }
        return min(max(width / height, 4.0 / 5.0), 1.91)
    }

    static func temporaryURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("post-\(UUID().uuidString).\(ext)")
    }
}

/// A video picked from the library, copied to a temporary file so it can be exported.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = PostMedia.temporaryURL(extension: received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

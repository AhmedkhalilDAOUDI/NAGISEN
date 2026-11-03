import AVFoundation
import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum PostMediaError: LocalizedError, Equatable {
    case unreadable
    case videoTooLong(seconds: Int)
    case tooLarge
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "That photo or video couldn't be opened.")
        case .videoTooLong(let seconds): String(localized: "Videos can be up to \(Int(PostMedia.maxVideoSeconds)) seconds. This one is \(seconds).")
        case .tooLarge: String(localized: "That file is over 50 MB, even after compressing it.")
        case .exportFailed: String(localized: "The video couldn't be prepared. Try a different one.")
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
        let output = temporaryURL(extension: "mp4")
        try await export(session, to: output)
        let bytes = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        try checkSize(bytes)
        return PostAttachment(kind: .video, fileURL: output, posterURL: await posterFrame(for: output))
    }

    private static func export(_ session: AVAssetExportSession, to output: URL) async throws {
        session.shouldOptimizeForNetworkUse = true
        if #available(iOS 18.0, *) {
            do { try await session.export(to: output, as: .mp4) } catch { throw PostMediaError.exportFailed }
        } else {
            session.outputURL = output
            session.outputFileType = .mp4
            await session.export()
            guard session.status == .completed else { throw PostMediaError.exportFailed }
        }
    }

    /// A photo or video straight from the camera, made ready to post like a picked one.
    static func attachment(from shot: Camera.Shot) async throws -> PostAttachment {
        switch shot {
        case .photo(let image):
            guard let data = image.jpegData(compressionQuality: 0.9) else { throw PostMediaError.unreadable }
            return try photo(from: data)
        case .video(let url):
            defer { try? FileManager.default.removeItem(at: url) }
            return try await video(at: url)
        }
    }

    static let cardVideoSeconds: Double = 15

    /// A finished card held still with one of the app's own tracks under it, as an .mp4 that plays
    /// anywhere. The music fades out over the last second and a half.
    static func cardVideo(_ image: UIImage, music: URL, seconds: Double = cardVideoSeconds) async throws -> URL {
        guard let picture = image.cgImage else { throw PostMediaError.unreadable }
        let fitted = scaledSize(CGSize(width: picture.width, height: picture.height), maxEdge: 1920)
        // H.264 needs even sides.
        let size = CGSize(width: (fitted.width / 2).rounded(.down) * 2, height: (fitted.height / 2).rounded(.down) * 2)
        let still = temporaryURL(extension: "mov")
        defer { try? FileManager.default.removeItem(at: still) }
        try await writeStill(picture, size: size, seconds: seconds, to: still)

        // Both assets stay in variables: a track whose asset is gone can't be copied.
        let movie = AVURLAsset(url: still), song = AVURLAsset(url: music)
        let composition = AVMutableComposition()
        guard let frames = try await movie.loadTracks(withMediaType: .video).first,
              let sound = try await song.loadTracks(withMediaType: .audio).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw PostMediaError.exportFailed }
        let length = CMTime(seconds: seconds, preferredTimescale: 600)
        let heard = min(length, try await song.load(.duration))
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: frames, at: .zero)
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: heard), of: sound, at: .zero)
        let fade = AVMutableAudioMixInputParameters(track: audioTrack)
        let fadeLength = CMTime(seconds: 1.5, preferredTimescale: 600)
        fade.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: heard - fadeLength, duration: fadeLength))
        let mix = AVMutableAudioMix()
        mix.inputParameters = [fade]
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw PostMediaError.exportFailed
        }
        session.audioMix = mix
        let output = temporaryURL(extension: "mp4")
        try await export(session, to: output)
        return output
    }

    /// A silent movie that shows one picture for `seconds`, one frame a second.
    private static func writeStill(_ picture: CGImage, size: CGSize, seconds: Double, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw PostMediaError.exportFailed }
        writer.add(input)
        guard writer.startWriting() else { throw PostMediaError.exportFailed }
        writer.startSession(atSourceTime: .zero)
        var made: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess,
              let buffer = made else { throw PostMediaError.exportFailed }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        // The card's rounded corners are see-through; a video has no see-through, so they sit on black.
        context?.setFillColor(UIColor.black.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        context?.draw(picture, in: CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        // One second past the end, so the movie is never a frame short of what gets cut from it.
        let last = Int(seconds.rounded(.up)) + 1
        for second in 0...last {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(second), timescale: 1)) else {
                throw PostMediaError.exportFailed
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(last), timescale: 1))
        await writer.finishWriting()
        guard writer.status == .completed else { throw PostMediaError.exportFailed }
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

    /// Width ÷ height a post's media is shown at: its own shape, so a card or a phone photo shows
    /// whole, but never taller than 9:16 or wider than 3:1; past those it sits whole inside that frame.
    static func feedAspectRatio(width: CGFloat, height: CGFloat) -> CGFloat {
        guard width > 0, height > 0 else { return 4.0 / 5.0 }
        return min(max(width / height, 9.0 / 16.0), 3)
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

/// The camera, one tap from a card, a post or a story. Where there is no camera (the simulator) it opens the library.
struct Camera: UIViewControllerRepresentable {
    enum Shot {
        case photo(UIImage)
        case video(URL)

        var image: UIImage? {
            if case .photo(let image) = self { return image }
            return nil
        }
    }

    var videos = false
    let onShot: (Shot?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        if videos {
            picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            picker.videoMaximumDuration = PostMedia.maxVideoSeconds
            picker.videoQuality = .typeHigh
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: Camera

        init(_ parent: Camera) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let movie = info[.mediaURL] as? URL {
                // The picker deletes its own file as soon as this returns.
                let copy = PostMedia.temporaryURL(extension: movie.pathExtension.isEmpty ? "mov" : movie.pathExtension)
                parent.onShot((try? FileManager.default.copyItem(at: movie, to: copy)) != nil ? .video(copy) : nil)
            } else {
                parent.onShot((info[.originalImage] as? UIImage).map(Shot.photo))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onShot(nil)
        }
    }
}

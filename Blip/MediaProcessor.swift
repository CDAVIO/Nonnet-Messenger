import AVFoundation
import UIKit

enum MediaProcessor {
    static let maxVideoSeconds: Double = 10

    /// Shrinks a photo to at most 1280 px on the long side, JPEG quality 0.5 (~100–200 KB).
    static func compressPhoto(_ data: Data) -> URL? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 1280 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.5) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        return (try? jpeg.write(to: url)) != nil ? url : nil
    }

    /// Speeds the clip up (x1, x1.5, x2), caps it at 10 s and re-encodes it at 360p. Video only, no sound.
    static func exportVideo(_ source: URL, speed: Double) async -> URL? {
        defer { try? FileManager.default.removeItem(at: source) }
        let asset = AVURLAsset(url: source)
        let composition = AVMutableComposition()
        do {
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)

            guard let video = try await asset.loadTracks(withMediaType: .video).first,
                  let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { return nil }
            try videoTrack.insertTimeRange(range, of: video, at: .zero)
            videoTrack.preferredTransform = try await video.load(.preferredTransform)

            let target = CMTimeMultiplyByFloat64(duration, multiplier: 1 / speed)
            if speed != 1 { composition.scaleTimeRange(range, toDuration: target) }

            // MediumQuality turns the 640x480 capture into 480x360 (360p).
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetMediumQuality) else { return nil }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
            export.outputURL = output
            export.outputFileType = .mp4
            export.shouldOptimizeForNetworkUse = true
            export.timeRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(target, CMTime(seconds: maxVideoSeconds, preferredTimescale: 600)))
            await withCheckedContinuation { done in
                export.exportAsynchronously { done.resume() }
            }
            return export.status == .completed ? output : nil
        } catch {
            return nil
        }
    }
}

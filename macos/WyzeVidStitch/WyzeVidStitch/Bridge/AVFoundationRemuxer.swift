import AVFoundation
import Foundation
import WyzeStitcherKit

/// Thread-safe handle tracking an active AVFoundation fallback session for instant cancellation.
private final class ActiveRemuxSession {
    var isCancelled: Bool = false
    weak var reader: AVAssetReader?
    weak var writer: AVAssetWriter?
}

/// Native Apple AVFoundation fallback implementing UniFFI's `AudioRemuxFallback` foreign trait.
/// Used automatically when legacy Wyze cameras emit non-AAC audio (e.g. μ-law PCM) or when
/// container-level `mp4-merge` reports a track incompatibility.
///
/// Strategy:
/// 1. Concatenate all source clips into an `AVMutableComposition`.
/// 2. Stream-copy the H.264/H.265 video track via `AVAssetReaderTrackOutput(outputSettings: nil)`
///    into `AVAssetWriterInput(outputSettings: nil)` (zero video transcoding).
/// 3. Decode legacy audio to Linear PCM and encode to standard 48kHz AAC-LC (`kAudioFormatMPEG4AAC`)
///    for universal QuickTime and `AVPlayerView` playback compatibility.
/// 4. Support instant cooperative abort via `cancelRemux(jobId:)`.
final class AVFoundationRemuxer: AudioRemuxFallback, @unchecked Sendable {
    private let onProgress: @Sendable (String, Float, UInt32, UInt32, String?) -> Void
    private let lock = NSLock()
    private var sessions: [String: ActiveRemuxSession] = [:]

    init(onProgress: @escaping @Sendable (String, Float, UInt32, UInt32, String?) -> Void) {
        self.onProgress = onProgress
    }

    func cancelRemux(jobId: String) {
        let session: ActiveRemuxSession? = lock.withLock {
            let s = sessions[jobId]
            s?.isCancelled = true
            return s
        }
        session?.reader?.cancelReading()
        session?.writer?.cancelWriting()
    }

    private func registerSession(for jobId: String) -> ActiveRemuxSession {
        lock.withLock {
            let session = ActiveRemuxSession()
            sessions[jobId] = session
            return session
        }
    }

    private func unregisterSession(for jobId: String) {
        lock.withLock {
            _ = sessions.removeValue(forKey: jobId)
        }
    }

    private func isCancelled(_ jobId: String) -> Bool {
        lock.withLock {
            sessions[jobId]?.isCancelled ?? false
        }
    }

    func remuxClipsToAac(
        jobId: String,
        inputClipPaths: [String],
        tempOutputPath: String
    ) async throws {
        guard !inputClipPaths.isEmpty else {
            throw StitcherError.FallbackRemuxFailed(reason: "No clips provided to AVFoundation remuxer.")
        }

        let session = registerSession(for: jobId)
        defer { unregisterSession(for: jobId) }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw StitcherError.FallbackRemuxFailed(reason: "Could not allocate composition video track.")
        }

        let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        let totalClips = UInt32(inputClipPaths.count)
        var hasAudio = false

        for (index, clipPath) in inputClipPaths.enumerated() {
            if isCancelled(jobId) || Task.isCancelled {
                throw StitcherError.Cancelled
            }

            let url = URL(fileURLWithPath: clipPath)
            let asset = AVURLAsset(url: url)

            let duration = try await asset.load(.duration)
            guard duration.isValid && duration > .zero else {
                throw StitcherError.FallbackRemuxFailed(
                    reason: "Corrupt or zero-duration clip detected: \(url.lastPathComponent). Inspect and exclude this minute to continue."
                )
            }

            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let srcVideo = try await asset.loadTracks(withMediaType: .video).first {
                try compVideoTrack.insertTimeRange(timeRange, of: srcVideo, at: cursor)
            }
            if let compAudioTrack,
               let srcAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try compAudioTrack.insertTimeRange(timeRange, of: srcAudio, at: cursor)
                hasAudio = true
            }

            cursor = CMTimeAdd(cursor, duration)

            let composeProgress = Float(index + 1) / Float(inputClipPaths.count) * 0.35
            onProgress(jobId, composeProgress, UInt32(index + 1), totalClips, url.lastPathComponent)
        }

        if isCancelled(jobId) || Task.isCancelled {
            throw StitcherError.Cancelled
        }

        let outputURL = URL(fileURLWithPath: tempOutputPath)
        try? FileManager.default.removeItem(at: outputURL)

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: composition)
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            writer.shouldOptimizeForNetworkUse = true
        } catch {
            throw StitcherError.FallbackRemuxFailed(reason: error.localizedDescription)
        }

        lock.withLock {
            session.reader = reader
            session.writer = writer
        }

        // Video passthrough (lossless stream copy — outputSettings: nil).
        let videoOutput = AVAssetReaderTrackOutput(track: compVideoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw StitcherError.FallbackRemuxFailed(reason: "AVAssetReader rejected passthrough video track.")
        }
        reader.add(videoOutput)

        let videoFormatHint = try await compVideoTrack.load(.formatDescriptions).first
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: nil,
            sourceFormatHint: videoFormatHint
        )
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw StitcherError.FallbackRemuxFailed(reason: "AVAssetWriter rejected passthrough video input.")
        }
        writer.add(videoInput)

        // Audio decode -> AAC-LC encode (if source clips contain audio).
        var audioPair: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
        if hasAudio, let compAudioTrack {
            let pcmSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let audioOutput = AVAssetReaderTrackOutput(track: compAudioTrack, outputSettings: pcmSettings)
            audioOutput.alwaysCopiesSampleData = false

            let aacSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
            audioInput.expectsMediaDataInRealTime = false

            if reader.canAdd(audioOutput) && writer.canAdd(audioInput) {
                reader.add(audioOutput)
                writer.add(audioInput)
                audioPair = (audioOutput, audioInput)
            }
        }

        guard writer.startWriting(), reader.startReading() else {
            let msg = writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "Failed to start AVFoundation pipeline."
            throw StitcherError.FallbackRemuxFailed(reason: msg)
        }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = max(CMTimeGetSeconds(cursor), 0.1)
        let progressCallback = self.onProgress

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            let videoQueue = DispatchQueue(label: "com.wyzevidstitch.avfoundation.video")
            let audioQueue = DispatchQueue(label: "com.wyzevidstitch.avfoundation.audio")

            group.enter()
            var videoFinished = false
            videoInput.requestMediaDataWhenReady(on: videoQueue) {
                while !videoFinished && videoInput.isReadyForMoreMediaData {
                    if self.isCancelled(jobId) {
                        videoFinished = true
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }
                    if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                        if pts.isFinite {
                            let remuxFraction = min(max(Float(pts / totalSeconds), 0), 1)
                            let overall = 0.35 + remuxFraction * 0.65
                            progressCallback(jobId, overall, totalClips, totalClips, "Remuxing AAC Audio...")
                        }
                        if !videoInput.append(sampleBuffer) {
                            videoFinished = true
                            videoInput.markAsFinished()
                            group.leave()
                            return
                        }
                    } else {
                        videoFinished = true
                        videoInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }

            if let (audioOutput, audioInput) = audioPair {
                group.enter()
                var audioFinished = false
                audioInput.requestMediaDataWhenReady(on: audioQueue) {
                    while !audioFinished && audioInput.isReadyForMoreMediaData {
                        if self.isCancelled(jobId) {
                            audioFinished = true
                            audioInput.markAsFinished()
                            group.leave()
                            return
                        }
                        if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                            if !audioInput.append(sampleBuffer) {
                                audioFinished = true
                                audioInput.markAsFinished()
                                group.leave()
                                return
                            }
                        } else {
                            audioFinished = true
                            audioInput.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }

            group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                if self.isCancelled(jobId) || writer.status == .cancelled {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(throwing: StitcherError.Cancelled)
                    return
                }

                writer.finishWriting {
                    if self.isCancelled(jobId) || writer.status == .cancelled {
                        try? FileManager.default.removeItem(at: outputURL)
                        continuation.resume(throwing: StitcherError.Cancelled)
                    } else if writer.status == .completed {
                        progressCallback(jobId, 1.0, totalClips, totalClips, nil)
                        continuation.resume()
                    } else {
                        let reason = writer.error?.localizedDescription
                            ?? reader.error?.localizedDescription
                            ?? "AVAssetWriter finished with status \(writer.status.rawValue)"
                        continuation.resume(throwing: StitcherError.FallbackRemuxFailed(reason: reason))
                    }
                }
            }
        }
    }
}

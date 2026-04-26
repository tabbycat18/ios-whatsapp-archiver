import AVFoundation
import AVKit
import ImageIO
import SwiftUI

struct MessageListView: View {
    let chat: ChatSummary
    let messages: [MessageRow]
    let isLoadingOlder: Bool
    let hasMoreOlderMessages: Bool
    let olderMessagesErrorMessage: String?
    let initialMessageLoadGeneration: Int
    let wallpaperURL: URL?
    let onLoadOlderMessages: () -> Void
    @StateObject private var audioPlayback = AudioPlaybackController()
    @State private var latestScrolledGeneration: Int?
    @State private var didCompleteInitialScroll = false
    @State private var lastOlderLoadTriggerMessageID: Int64?
    private let olderLoadThreshold = 8

    var body: some View {
        ZStack {
            ChatWallpaperBackgroundView(wallpaperURL: wallpaperURL)

            ScrollViewReader { proxy in
                List {
                    olderPaginationStatus

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        MessageBubbleView(message: message, isGroupChat: chat.isGroupChat)
                            .environmentObject(audioPlayback)
                            .id(message.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                            .listRowBackground(Color.clear)
                            .onAppear {
                                loadOlderMessagesIfNeeded(appearingAt: index)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .onAppear {
                    scrollToLatestMessageIfNeeded(using: proxy, animated: false)
                }
                .onChange(of: initialMessageLoadGeneration) { _, _ in
                    didCompleteInitialScroll = false
                    lastOlderLoadTriggerMessageID = nil
                    scrollToLatestMessageIfNeeded(using: proxy, animated: false)
                }
            }
        }
        .navigationTitle(chat.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var olderPaginationStatus: some View {
        if isLoadingOlder || olderMessagesErrorMessage != nil {
            HStack(spacing: 8) {
                Spacer(minLength: 0)

                if isLoadingOlder {
                    ProgressView()
                        .controlSize(.small)
                }

                if let olderMessagesErrorMessage, !olderMessagesErrorMessage.isEmpty {
                    Text(olderMessagesErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else if isLoadingOlder {
                    Text("Loading older messages...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private func scrollToLatestMessageIfNeeded(using proxy: ScrollViewProxy, animated: Bool) {
        guard latestScrolledGeneration != initialMessageLoadGeneration else { return }
        latestScrolledGeneration = initialMessageLoadGeneration
        guard let latestMessageID = messages.last?.id else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation {
                    proxy.scrollTo(latestMessageID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(latestMessageID, anchor: .bottom)
            }
            didCompleteInitialScroll = true
        }
    }

    private func loadOlderMessagesIfNeeded(appearingAt index: Int) {
        guard didCompleteInitialScroll, hasMoreOlderMessages, !isLoadingOlder else { return }
        guard index < olderLoadThreshold else { return }
        guard let oldestMessageID = messages.first?.id else { return }
        guard lastOlderLoadTriggerMessageID != oldestMessageID else { return }
        lastOlderLoadTriggerMessageID = oldestMessageID
        onLoadOlderMessages()
    }
}

private struct ChatWallpaperBackgroundView: View {
    let wallpaperURL: URL?
    @State private var image: CGImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            Color.gray.opacity(0.08)

            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.9)
            }
        }
        .ignoresSafeArea()
        .task(id: wallpaperURL) {
            await loadWallpaperIfNeeded()
        }
    }

    private func loadWallpaperIfNeeded() async {
        guard image == nil, !didFail, let wallpaperURL else {
            return
        }

        let loadedImage = await Task.detached(priority: .utility) {
            downsampleImage(at: wallpaperURL, maxPixelSize: 1800)
        }.value

        if let loadedImage {
            image = loadedImage
        } else {
            didFail = true
        }
    }
}

@MainActor
private final class AudioPlaybackController: ObservableObject {
    @Published private(set) var playingMessageID: Int64?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func isPlaying(_ messageID: Int64) -> Bool {
        playingMessageID == messageID
    }

    func toggle(messageID: Int64, url: URL) {
        if playingMessageID == messageID {
            stop()
            return
        }

        stop()
        prepareMediaPlaybackSession()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        playingMessageID = messageID
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }
        player.play()
    }

    func stop() {
        player?.pause()
        player = nil
        playingMessageID = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

private struct MessageBubbleView: View {
    let message: MessageRow
    let isGroupChat: Bool
    @EnvironmentObject private var audioPlayback: AudioPlaybackController

    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 36)
            }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
                if let senderLabel {
                    Text(senderLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                MessageContentView(message: message)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isFromMe ? Color.green.opacity(0.18) : Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .textSelection(.enabled)

                if let messageDate = message.messageDate {
                    Text(Self.dateFormatter.string(from: messageDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !message.isFromMe {
                Spacer(minLength: 36)
            }
        }
        .padding(.vertical, 1)
        .onDisappear {
            if audioPlayback.isPlaying(message.id) {
                audioPlayback.stop()
            }
        }
    }

    private var senderLabel: String? {
        if message.isFromMe {
            return "You"
        }
        if isGroupChat {
            if let friendlyName = DisplayNameSanitizer.friendlyName(message.friendlySenderName) {
                return friendlyName
            }
            return message.safeSenderPhoneNumber ?? "Unknown sender"
        }
        return nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct MessageContentView: View {
    let message: MessageRow

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 6) {
            if let media = message.media, shouldShowAttachment(for: media) {
                attachmentView(for: media)
            }

            if let displayText {
                Text(displayText)
                    .textSelection(.enabled)
            } else if message.media == nil {
                Text(message.nonTextPlaceholderText ?? "Unsupported message")
                    .textSelection(.enabled)
            }
        }
    }

    private var displayText: String? {
        guard let text = message.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    private func shouldShowAttachment(for media: MediaMetadata) -> Bool {
        switch media.kind {
        case .photo, .video, .audio:
            return true
        case .contact, .location, .sticker, .document, .linkPreview, .call, .callOrSystem, .system, .deleted, .media:
            return displayText == nil
        }
    }

    @ViewBuilder
    private func attachmentView(for media: MediaMetadata) -> some View {
        switch media.kind {
        case .photo:
            PhotoAttachmentView(media: media)
        case .video:
            VideoAttachmentView(media: media)
        case .audio:
            AudioAttachmentView(messageID: message.id, media: media)
        default:
            Text(media.kind.placeholderText)
                .textSelection(.enabled)
        }
    }
}

private struct PhotoAttachmentView: View {
    let media: MediaMetadata
    @State private var image: CGImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if !media.isFileAvailableInArchive || media.fileURL == nil {
                AttachmentPlaceholderView(title: "Photo unavailable", systemImage: "photo")
            } else if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Photo attachment")
            } else if didFail {
                AttachmentPlaceholderView(title: "Photo unavailable", systemImage: "photo")
            } else {
                AttachmentPlaceholderView(title: "Loading photo", systemImage: "photo")
            }
        }
        .task(id: media.fileURL) {
            await loadImageIfNeeded()
        }
    }

    private func loadImageIfNeeded() async {
        guard image == nil, !didFail, let url = media.fileURL, media.isFileAvailableInArchive else {
            return
        }

        let loadedImage = await Task.detached(priority: .utility) {
            downsampleImage(at: url, maxPixelSize: 900)
        }.value

        if let loadedImage {
            image = loadedImage
        } else {
            didFail = true
        }
    }
}

private struct VideoAttachmentView: View {
    let media: MediaMetadata
    @State private var thumbnail: CGImage?
    @State private var didFailThumbnail = false
    @State private var playbackItem: VideoPlaybackItem?

    var body: some View {
        Group {
            if !media.isFileAvailableInArchive || media.fileURL == nil {
                AttachmentPlaceholderView(title: "Video unavailable", systemImage: "video")
            } else {
                Button {
                    if let url = media.fileURL {
                        playbackItem = VideoPlaybackItem(url: url)
                    }
                } label: {
                    ZStack {
                        if let thumbnail {
                            Image(decorative: thumbnail, scale: 1, orientation: .up)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Rectangle()
                                .fill(Color.black.opacity(0.72))
                        }

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)

                        if thumbnail == nil && !didFailThumbnail {
                            ProgressView()
                                .tint(.white)
                                .offset(y: 46)
                        }
                    }
                    .frame(width: 260, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Video attachment")
                }
                .buttonStyle(.plain)
                .task(id: media.fileURL) {
                    await loadThumbnailIfNeeded()
                }
                .sheet(item: $playbackItem) { item in
                    VideoPlayerSheet(url: item.url)
                }
            }
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard thumbnail == nil, !didFailThumbnail, let url = media.fileURL, media.isFileAvailableInArchive else {
            return
        }

        let loadedThumbnail = await videoThumbnail(at: url, maxPixelSize: 720)

        if let loadedThumbnail {
            thumbnail = loadedThumbnail
        } else {
            didFailThumbnail = true
        }
    }

}

private struct VideoPlaybackItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct VideoPlayerSheet: View {
    @StateObject private var controller: VideoPlaybackController

    init(url: URL) {
        _controller = StateObject(wrappedValue: VideoPlaybackController(url: url))
    }

    var body: some View {
        VideoPlayer(player: controller.player)
            .ignoresSafeArea()
        .onAppear {
            controller.play()
        }
        .onDisappear {
            controller.pause()
        }
    }
}

@MainActor
private final class VideoPlaybackController: ObservableObject {
    let player: AVPlayer

    init(url: URL) {
        self.player = AVPlayer(url: url)
    }

    func play() {
        prepareMediaPlaybackSession()
        player.play()
    }

    func pause() {
        player.pause()
    }
}

private struct AudioAttachmentView: View {
    let messageID: Int64
    let media: MediaMetadata
    @EnvironmentObject private var audioPlayback: AudioPlaybackController

    var body: some View {
        if !media.isFileAvailableInArchive || media.fileURL == nil {
            AttachmentPlaceholderView(title: "Audio unavailable", systemImage: "waveform")
        } else {
            Button {
                if let url = media.fileURL {
                    audioPlayback.toggle(messageID: messageID, url: url)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: audioPlayback.isPlaying(messageID) ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio")
                            .font(.subheadline)
                        if let durationText {
                            Text(durationText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: 220)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Audio attachment")
        }
    }

    private var durationText: String? {
        guard let durationSeconds = media.durationSeconds, durationSeconds > 0 else {
            return nil
        }
        let seconds = Int(durationSeconds.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct AttachmentPlaceholderView: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 260, minHeight: 44, alignment: .leading)
    }
}

private func downsampleImage(at url: URL, maxPixelSize: CGFloat) -> CGImage? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
        return nil
    }

    let downsampleOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary

    return CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions)
}

private func videoThumbnail(at url: URL, maxPixelSize: CGFloat) async -> CGImage? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
    return try? await generator.image(at: .zero).image
}

private func prepareMediaPlaybackSession() {
    #if os(iOS)
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    try? AVAudioSession.sharedInstance().setActive(true)
    #endif
}

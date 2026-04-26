import AVFoundation
import AVKit
import ImageIO
import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    @State private var messageSearchText = ""
    @State private var latestScrolledSearchQuery = ""
    @State private var latestScrolledSearchResultID: Int64?
    private let olderLoadThreshold = 8
    private let bottomSpacerID = "message-list-bottom-spacer"

    private var trimmedMessageSearchText: String {
        messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchingMessages: Bool {
        !trimmedMessageSearchText.isEmpty
    }

    private var displayedMessages: [(offset: Int, element: MessageRow)] {
        let enumeratedMessages = Array(messages.enumerated())
        guard isSearchingMessages else {
            return enumeratedMessages
        }
        return enumeratedMessages.filter { _, message in
            message.matchesSearch(trimmedMessageSearchText)
        }
    }

    var body: some View {
        ZStack {
            ChatWallpaperBackgroundView(wallpaperURL: wallpaperURL)

            ScrollViewReader { proxy in
                List {
                    if isSearchingMessages, displayedMessages.isEmpty {
                        noMessageSearchResults
                    } else {
                        olderPaginationStatus

                        ForEach(displayedMessages, id: \.element.id) { index, message in
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

                        messageListBottomSpacer
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
                .onChange(of: trimmedMessageSearchText) { _, _ in
                    scrollToFirstSearchResultIfNeeded(using: proxy)
                }
                .onChange(of: displayedMessages.first?.element.id) { _, _ in
                    scrollToFirstSearchResultIfNeeded(using: proxy)
                }
            }
        }
        .navigationTitle(chat.title)
        .searchable(text: $messageSearchText, prompt: "Search messages")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var noMessageSearchResults: some View {
        Text("No loaded messages match")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var messageListBottomSpacer: some View {
        Color.clear
            .frame(height: 32)
            .id(bottomSpacerID)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var olderPaginationStatus: some View {
        if !isSearchingMessages, isLoadingOlder || olderMessagesErrorMessage != nil {
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
        guard !messages.isEmpty else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation {
                    proxy.scrollTo(bottomSpacerID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomSpacerID, anchor: .bottom)
            }
            didCompleteInitialScroll = true
        }
    }

    private func loadOlderMessagesIfNeeded(appearingAt index: Int) {
        guard !isSearchingMessages else { return }
        guard didCompleteInitialScroll, hasMoreOlderMessages, !isLoadingOlder else { return }
        guard index < olderLoadThreshold else { return }
        guard let oldestMessageID = messages.first?.id else { return }
        guard lastOlderLoadTriggerMessageID != oldestMessageID else { return }
        lastOlderLoadTriggerMessageID = oldestMessageID
        onLoadOlderMessages()
    }

    private func scrollToFirstSearchResultIfNeeded(using proxy: ScrollViewProxy) {
        guard isSearchingMessages else {
            latestScrolledSearchQuery = ""
            latestScrolledSearchResultID = nil
            return
        }
        guard let firstResultID = displayedMessages.first?.element.id else { return }
        guard latestScrolledSearchQuery != trimmedMessageSearchText || latestScrolledSearchResultID != firstResultID else { return }
        latestScrolledSearchQuery = trimmedMessageSearchText
        latestScrolledSearchResultID = firstResultID
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(firstResultID, anchor: .center)
            }
        }
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

private extension MessageRow {
    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [
            text,
            nonTextPlaceholderText,
            friendlySenderName,
            safeSenderPhoneNumber
        ]
        .compactMap { $0 }
        .contains { $0.localizedStandardContains(query) }
    }
}

@MainActor
private final class AudioPlaybackController: ObservableObject {
    @Published private(set) var playingMessageID: Int64?
    @Published private(set) var pausedMessageID: Int64?
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var durationSeconds: Double?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?

    deinit {
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func isPlaying(_ messageID: Int64) -> Bool {
        playingMessageID == messageID
    }

    func toggle(messageID: Int64, url: URL) {
        if playingMessageID == messageID {
            pause()
            return
        }

        if pausedMessageID == messageID, player != nil {
            resume(messageID: messageID)
            return
        }

        stop()
        prepareMediaPlaybackSession()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        playingMessageID = messageID
        pausedMessageID = nil
        durationSeconds = nil
        currentTimeSeconds = 0
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak item] time in
            Task { @MainActor in
                self?.updateProgress(currentTime: time.seconds, item: item)
            }
        }
        player.play()
    }

    func seek(messageID: Int64, to seconds: Double) {
        guard (playingMessageID == messageID || pausedMessageID == messageID), let player else { return }
        let clampedSeconds = max(0, min(seconds, durationSeconds ?? seconds))
        currentTimeSeconds = clampedSeconds
        player.seek(to: CMTime(seconds: clampedSeconds, preferredTimescale: 600))
    }

    func stop() {
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player?.pause()
        player = nil
        playingMessageID = nil
        pausedMessageID = nil
        currentTimeSeconds = 0
        durationSeconds = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func pause() {
        player?.pause()
        pausedMessageID = playingMessageID
        playingMessageID = nil
    }

    private func resume(messageID: Int64) {
        prepareMediaPlaybackSession()
        playingMessageID = messageID
        pausedMessageID = nil
        player?.play()
    }

    private func updateProgress(currentTime: Double, item: AVPlayerItem?) {
        guard currentTime.isFinite else { return }
        currentTimeSeconds = max(0, currentTime)

        guard let item else { return }
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0 {
            durationSeconds = duration
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
                    .background(message.isFromMe ? Color(red: 0.86, green: 0.95, blue: 0.84) : Color.white.opacity(0.94))
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
        case .contact:
            ContactAttachmentView(media: media)
        default:
            Text(media.kind.placeholderText)
                .textSelection(.enabled)
        }
    }
}

private struct ContactAttachmentView: View {
    let media: MediaMetadata

    private var displayName: String {
        media.contactDisplayName ?? "Shared contact"
    }

    private var initials: String? {
        let letters = displayName
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap { word -> String? in
                guard let letter = word.first(where: \.isLetter) else { return nil }
                return String(letter)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .uppercased()
            }
            .prefix(2)
            .joined()
        return letters.isEmpty ? nil : letters
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))

                if let initials {
                    Text(initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)

                Text("Contact card")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 260, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct PhotoAttachmentView: View {
    let media: MediaMetadata
    @State private var image: CGImage?
    @State private var didFail = false
    @State private var previewItem: PhotoPreviewItem?

    var body: some View {
        Group {
            if !media.isFileAvailableInArchive || media.fileURL == nil {
                AttachmentPlaceholderView(title: "Photo unavailable", systemImage: "photo")
            } else if let image {
                Button {
                    if let url = media.fileURL {
                        previewItem = PhotoPreviewItem(url: url)
                    }
                } label: {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open photo attachment")
            } else if didFail {
                AttachmentPlaceholderView(title: "Photo unavailable", systemImage: "photo")
            } else {
                AttachmentPlaceholderView(title: "Loading photo", systemImage: "photo")
            }
        }
        .task(id: media.fileURL) {
            await loadImageIfNeeded()
        }
        .sheet(item: $previewItem) { item in
            PhotoPreviewView(url: item.url)
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

private struct PhotoPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PhotoPreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var didFail = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            Group {
                if let image {
                    #if os(iOS)
                    ZoomableImageView(image: image)
                        .ignoresSafeArea()
                        .accessibilityLabel("Photo attachment")
                    #else
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .accessibilityLabel("Photo attachment")
                    #endif
                } else if didFail {
                    AttachmentPlaceholderView(title: "Photo unavailable", systemImage: "photo")
                        .padding()
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white, .black.opacity(0.35))
                }
                .accessibilityLabel("Close photo")

                Spacer()

                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white, .black.opacity(0.35))
                }
                .accessibilityLabel("Share photo")
            }
            .padding()
        }
        .task {
            await loadPreviewImage()
        }
    }

    private func loadPreviewImage() async {
        guard image == nil, !didFail else {
            return
        }

        let loadedImage = await Task.detached(priority: .utility) {
            downsampleImage(at: url, maxPixelSize: 2400)
        }.value

        if let loadedImage {
            image = loadedImage
        } else {
            didFail = true
        }
    }
}

#if os(iOS)
private struct ZoomableImageView: UIViewRepresentable {
    let image: CGImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black

        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let imageIdentifier = "\(image.width)x\(image.height)"
        if context.coordinator.imageIdentifier != imageIdentifier {
            context.coordinator.imageIdentifier = imageIdentifier
            scrollView.setZoomScale(1, animated: false)
        }
        context.coordinator.imageView.image = UIImage(cgImage: image)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        var imageIdentifier: String?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
    }
}
#endif

private struct VideoAttachmentView: View {
    let media: MediaMetadata
    @StateObject private var playbackController = VideoPlaybackController()
    @State private var thumbnail: CGImage?
    @State private var didFailThumbnail = false
    @State private var isPlayerPresented = false

    var body: some View {
        Group {
            if !media.isFileAvailableInArchive || media.fileURL == nil {
                AttachmentPlaceholderView(title: "Video unavailable", systemImage: "video")
            } else {
                Button {
                    if let url = media.fileURL {
                        playbackController.load(url: url, restart: true)
                        isPlayerPresented = true
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
                .sheet(isPresented: $isPlayerPresented) {
                    if let url = media.fileURL {
                        VideoPlayerSheet(controller: playbackController, url: url)
                    }
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

private struct VideoPlayerSheet: View {
    @ObservedObject var controller: VideoPlaybackController
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            VideoPlayer(player: controller.player)
                .ignoresSafeArea()

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white, .black.opacity(0.35))
                }
                .accessibilityLabel("Close video")

                Spacer()

                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white, .black.opacity(0.35))
                }
                .accessibilityLabel("Share video")
            }
            .padding()
        }
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
    private(set) var player = AVPlayer()
    private var loadedURL: URL?

    func load(url: URL, restart: Bool) {
        guard loadedURL != url else {
            if restart {
                player.seek(to: .zero)
            }
            return
        }

        player.pause()
        player = AVPlayer(url: url)
        loadedURL = url
    }

    func play() {
        guard loadedURL != nil else { return }
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
    @State private var scrubberValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        if !media.isFileAvailableInArchive || media.fileURL == nil {
            AttachmentPlaceholderView(title: "Audio unavailable", systemImage: "waveform")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if let url = media.fileURL {
                        audioPlayback.toggle(messageID: messageID, url: url)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: audioPlayback.isPlaying(messageID) ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)

                        Text("Audio")
                            .font(.subheadline)

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Audio attachment")

                Slider(
                    value: Binding(
                        get: { scrubberDisplayValue },
                        set: { scrubberValue = $0 }
                    ),
                    in: 0...max(scrubberDuration, 1),
                    onEditingChanged: handleScrubEditingChanged
                )

                HStack {
                    Text(Self.timeFormatter(currentTimeSeconds))
                    Spacer(minLength: 0)
                    Text(Self.timeFormatter(scrubberDuration))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(width: 230)
            .onChange(of: audioPlayback.currentTimeSeconds) { _, newValue in
                guard audioPlayback.isPlaying(messageID), !isScrubbing else { return }
                scrubberValue = newValue
            }
            .onChange(of: audioPlayback.playingMessageID) { _, playingMessageID in
                guard playingMessageID != messageID, audioPlayback.pausedMessageID != messageID else { return }
                scrubberValue = 0
                isScrubbing = false
            }
        }
    }

    private var currentTimeSeconds: Double {
        guard audioPlayback.isPlaying(messageID) || audioPlayback.pausedMessageID == messageID else {
            return 0
        }
        return audioPlayback.currentTimeSeconds
    }

    private var scrubberDuration: Double {
        (audioPlayback.isPlaying(messageID) || audioPlayback.pausedMessageID == messageID)
            ? (audioPlayback.durationSeconds ?? media.durationSeconds ?? 0)
            : (media.durationSeconds ?? 0)
    }

    private var scrubberDisplayValue: Double {
        if isScrubbing {
            return scrubberValue
        }
        return (audioPlayback.isPlaying(messageID) || audioPlayback.pausedMessageID == messageID)
            ? audioPlayback.currentTimeSeconds
            : 0
    }

    private func handleScrubEditingChanged(_ editing: Bool) {
        isScrubbing = editing
        guard !editing else { return }
        if let url = media.fileURL, !audioPlayback.isPlaying(messageID) {
            audioPlayback.toggle(messageID: messageID, url: url)
        }
        audioPlayback.seek(messageID: messageID, to: scrubberValue)
    }

    private static func timeFormatter(_ value: Double) -> String {
        guard value.isFinite, value > 0 else {
            return "0:00"
        }
        let seconds = Int(value.rounded())
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

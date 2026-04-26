import AVFoundation
import AVKit
import ImageIO
import SwiftUI
#if os(iOS)
import QuickLook
import UIKit
#endif

struct MessageListView: View {
    @EnvironmentObject private var store: ArchiveStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var isChatInfoPresented = false
    @State private var edgeBackDragOffset: CGFloat = 0
    private let olderLoadThreshold = 8
    private let bottomSpacerID = "message-list-bottom-spacer"
    private let edgeBackStartWidth: CGFloat = 24
    private let edgeBackMaxOffset: CGFloat = 52
    private let edgeBackDismissThreshold: CGFloat = 44

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
        .offset(x: edgeBackDragOffset)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: edgeBackDragOffset)
        .contentShape(Rectangle())
        .simultaneousGesture(edgeBackGesture)
        .navigationTitle(chat.title)
        .searchable(text: $messageSearchText, prompt: "Search messages")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isChatInfoPresented = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Chat info")
            }
        }
        .sheet(isPresented: $isChatInfoPresented) {
            ChatInfoView(chat: chat)
                .environmentObject(store)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var edgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard shouldHandleEdgeBackDrag(value) else {
                    if edgeBackDragOffset > 0 {
                        edgeBackDragOffset = 0
                    }
                    return
                }

                edgeBackDragOffset = min(max(value.translation.width, 0), edgeBackMaxOffset)
            }
            .onEnded { value in
                let shouldDismiss = shouldHandleEdgeBackDrag(value)
                    && value.translation.width >= edgeBackDismissThreshold

                if shouldDismiss {
                    edgeBackDragOffset = edgeBackMaxOffset
                    dismiss()
                } else {
                    edgeBackDragOffset = 0
                }
            }
    }

    private func shouldHandleEdgeBackDrag(_ value: DragGesture.Value) -> Bool {
        guard horizontalSizeClass == .compact else { return false }
        guard value.startLocation.x <= edgeBackStartWidth else { return false }
        guard value.translation.width > 0 else { return false }

        let horizontalDistance = value.translation.width
        let verticalDistance = abs(value.translation.height)
        return horizontalDistance > verticalDistance * 1.2
    }

    private var noMessageSearchResults: some View {
        Text("No loaded messages match")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var messageListBottomSpacer: some View {
        Color.clear
            .frame(height: 16)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation {
                    proxy.scrollTo(firstResultID, anchor: .center)
                }
            }
        }
    }
}

private struct ChatWallpaperBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    let wallpaperURL: URL?
    @State private var image: CGImage?
    @State private var didFail = false
    @State private var loadedWallpaperURL: URL?

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
        .task(id: resolvedWallpaperURL) {
            await loadWallpaperIfNeeded()
        }
    }

    private var resolvedWallpaperURL: URL? {
        guard let wallpaperURL else { return nil }
        guard colorScheme == .dark, wallpaperURL.lastPathComponent == "current_wallpaper.jpg" else {
            return wallpaperURL
        }

        let darkWallpaperURL = wallpaperURL
            .deletingLastPathComponent()
            .appendingPathComponent("current_wallpaper_dark.jpg")
            .standardizedFileURL
        return FileManager.default.fileExists(atPath: darkWallpaperURL.path) ? darkWallpaperURL : wallpaperURL
    }

    private func loadWallpaperIfNeeded() async {
        let wallpaperURL = resolvedWallpaperURL
        if loadedWallpaperURL != wallpaperURL {
            image = nil
            didFail = false
            loadedWallpaperURL = wallpaperURL
        }

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

private struct ChatInfoView: View {
    @EnvironmentObject private var store: ArchiveStore
    @Environment(\.dismiss) private var dismiss
    let chat: ChatSummary
    @State private var selectedFilter: ChatMediaFilter = .all
    @State private var mediaItems: [ChatMediaItem] = []
    @State private var mediaSummary: ChatMediaLoadSummary?
    @State private var mediaLoadError: String?
    @State private var thumbnailFailureIDs = Set<String>()
    @State private var isSelectingMedia = false
    @State private var selectedMediaIDs = Set<String>()
    @State private var mediaShareSelection: MediaShareSelection?
    @State private var mediaTileFrames: [String: CGRect] = [:]
    @State private var selectionDragMode: MediaSelectionDragMode?
    @State private var selectionDragVisitedIDs = Set<String>()
    @State private var selectionDragIntent: MediaSelectionDragIntent?

    private var mediaTaskID: String {
        "\(chat.id)-\(selectedFilter.rawValue)"
    }

    private var exportableMediaItems: [ChatMediaItem] {
        mediaItems.filter { item in
            item.media.fileURL != nil && item.media.isFileAvailableInArchive
        }
    }

    private var selectedExportURLs: [URL] {
        mediaItems.compactMap { item in
            guard selectedMediaIDs.contains(item.id),
                  item.media.isFileAvailableInArchive else {
                return nil
            }
            return item.media.fileURL
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Title", value: chat.title)
                    LabeledContent("Messages", value: chat.messageCount.formatted())
                    if chat.classification == .statusStoryFragment {
                        LabeledContent("Type", value: "Stories")
                    }
                }

                Section("Media") {
                    Picker("Media", selection: $selectedFilter) {
                        ForEach(ChatMediaFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let mediaLoadError {
                        Text(mediaLoadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if mediaItems.isEmpty {
                        Text("No media")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if let summaryText {
                            Text(summaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        mediaSelectionControls

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(mediaItems) { item in
                                ChatInfoMediaTile(
                                    item: item,
                                    isSelectionMode: isSelectingMedia,
                                    isSelected: selectedMediaIDs.contains(item.id),
                                    onToggleSelection: {
                                        toggleMediaSelection(item)
                                    }
                                ) {
                                    thumbnailFailureIDs.insert(item.id)
                                }
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: ChatInfoMediaTileFramePreferenceKey.self,
                                            value: [item.id: proxy.frame(in: .named("chatInfoMediaGrid"))]
                                        )
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                        .coordinateSpace(name: "chatInfoMediaGrid")
                        .onPreferenceChange(ChatInfoMediaTileFramePreferenceKey.self) { frames in
                            mediaTileFrames = frames
                        }
                        .mediaSelectionDrag(isSelectingMedia, gesture: mediaSelectionDragGesture)
                    }
                }
            }
            .navigationTitle(chat.classification == .statusStoryFragment ? "Stories" : "Chat Info")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task(id: mediaTaskID) {
                loadMediaItems()
            }
            #if os(iOS)
            .sheet(item: $mediaShareSelection) { selection in
                ActivityView(activityItems: selection.urls)
            }
            #endif
        }
    }

    @ViewBuilder
    private var mediaSelectionControls: some View {
        HStack(spacing: 8) {
            Text(isSelectingMedia ? selectionSummaryText : exportableSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if isSelectingMedia {
                Spacer(minLength: 4)

                compactMediaButton(systemImage: "checkmark.circle.fill", title: "Select all") {
                    selectAllExportableMedia()
                }
                .disabled(exportableMediaItems.isEmpty)

                compactMediaButton(systemImage: "xmark.circle", title: "Clear selection") {
                    selectedMediaIDs = []
                }
                .disabled(selectedMediaIDs.isEmpty)

                compactMediaButton(systemImage: "square.and.arrow.up", title: "Share selected") {
                    shareSelectedMedia()
                }
                .disabled(selectedExportURLs.isEmpty)
            } else {
                Spacer(minLength: 4)
            }

            compactMediaButton(systemImage: isSelectingMedia ? "checkmark.circle" : "checkmark.circle", title: isSelectingMedia ? "Done selecting" : "Select media") {
                isSelectingMedia.toggle()
                if !isSelectingMedia {
                    selectedMediaIDs = []
                    resetSelectionDrag()
                }
            }
        }
    }

    private func compactMediaButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 36, height: 32)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var summaryText: String? {
        guard let mediaSummary else { return nil }
        var parts = ["Showing \(mediaSummary.displayedRows.formatted()) items"]
        if mediaSummary.missingOrUnresolvedRows > 0 {
            parts.append("\(mediaSummary.missingOrUnresolvedRows.formatted()) unavailable")
        }
        if !thumbnailFailureIDs.isEmpty {
            parts.append("\(thumbnailFailureIDs.count.formatted()) thumbnail failed")
        }
        return parts.joined(separator: " • ")
    }

    private func loadMediaItems() {
        do {
            let page = try store.mediaLibraryPage(for: chat, filter: selectedFilter)
            mediaItems = page.items
            mediaSummary = page.summary
            thumbnailFailureIDs = []
            selectedMediaIDs = selectedMediaIDs.intersection(Set(page.items.map(\.id)))
            if page.items.isEmpty {
                isSelectingMedia = false
            }
            mediaLoadError = nil
            logMediaSummary(page.summary)
        } catch {
            mediaItems = []
            mediaSummary = nil
            thumbnailFailureIDs = []
            selectedMediaIDs = []
            isSelectingMedia = false
            mediaLoadError = "Could not load media."
        }
    }

    private var selectionSummaryText: String {
        let selectedCount = selectedMediaIDs.count
        let exportableCount = selectedExportURLs.count
        if selectedCount == exportableCount {
            return "\(selectedCount.formatted()) selected"
        }
        return "\(selectedCount.formatted()) selected • \(exportableCount.formatted()) exportable"
    }

    private var exportableSummaryText: String {
        let exportableCount = exportableMediaItems.count
        if exportableCount == mediaItems.count {
            return "\(exportableCount.formatted()) available"
        }
        return "\(exportableCount.formatted()) available • \(mediaItems.count.formatted()) shown"
    }

    private func toggleMediaSelection(_ item: ChatMediaItem) {
        guard item.media.fileURL != nil, item.media.isFileAvailableInArchive else {
            return
        }
        if selectedMediaIDs.contains(item.id) {
            selectedMediaIDs.remove(item.id)
        } else {
            selectedMediaIDs.insert(item.id)
        }
    }

    private func selectAllExportableMedia() {
        selectedMediaIDs = Set(exportableMediaItems.map(\.id))
    }

    private func shareSelectedMedia() {
        let urls = selectedExportURLs
        guard !urls.isEmpty else { return }
        mediaShareSelection = MediaShareSelection(urls: urls)
    }

    private var mediaSelectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("chatInfoMediaGrid"))
            .onChanged { value in
                guard isSelectingMedia else { return }
                guard shouldHandleSelectionDrag(value) else { return }
                updateSelectionDrag(at: value.location)
            }
            .onEnded { _ in
                resetSelectionDrag()
            }
    }

    private func shouldHandleSelectionDrag(_ value: DragGesture.Value) -> Bool {
        if selectionDragIntent == nil {
            let horizontalDistance = abs(value.translation.width)
            let verticalDistance = abs(value.translation.height)
            selectionDragIntent = horizontalDistance > verticalDistance * 1.15 ? .selecting : .scrolling
        }
        return selectionDragIntent == .selecting
    }

    private func updateSelectionDrag(at location: CGPoint) {
        guard let item = mediaItems.first(where: { item in
            mediaTileFrames[item.id]?.contains(location) == true
        }) else {
            return
        }
        guard item.media.fileURL != nil, item.media.isFileAvailableInArchive else {
            return
        }
        guard !selectionDragVisitedIDs.contains(item.id) else {
            return
        }

        if selectionDragMode == nil {
            selectionDragMode = selectedMediaIDs.contains(item.id) ? .remove : .add
        }
        selectionDragVisitedIDs.insert(item.id)

        switch selectionDragMode {
        case .add:
            selectedMediaIDs.insert(item.id)
        case .remove:
            selectedMediaIDs.remove(item.id)
        case nil:
            break
        }
    }

    private func resetSelectionDrag() {
        selectionDragMode = nil
        selectionDragVisitedIDs = []
        selectionDragIntent = nil
    }

    private func logMediaSummary(_ summary: ChatMediaLoadSummary) {
        #if DEBUG
        print(
            """
            Media library counts: filter=\(selectedFilter.rawValue) matching=\(summary.totalRowsMatchingFilter) scanned=\(summary.rowsScanned) displayed=\(summary.displayedRows) local=\(summary.rowsWithLocalPath) photo=\(summary.photoRows) video=\(summary.videoRows) audio=\(summary.audioRows) other=\(summary.otherRows) resolved=\(summary.resolvedFileURLRows) exists=\(summary.existingFileRows) readable=\(summary.readableFileRows) missing=\(summary.missingOrUnresolvedRows) statusExcluded=\(summary.statusStoryRowsExcluded) capMayHideRows=\(summary.queryCapMayHideRows)
            """
        )
        #endif
    }
}

private struct MediaShareSelection: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private enum MediaSelectionDragMode {
    case add
    case remove
}

private enum MediaSelectionDragIntent {
    case selecting
    case scrolling
}

private extension View {
    @ViewBuilder
    func mediaSelectionDrag<SelectionGesture: Gesture>(
        _ isEnabled: Bool,
        gesture: SelectionGesture
    ) -> some View {
        if isEnabled {
            simultaneousGesture(gesture)
        } else {
            self
        }
    }
}

private struct ChatInfoMediaTileFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

#if os(iOS)
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
    }
}
#endif

private struct ChatInfoMediaTile: View {
    let item: ChatMediaItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onThumbnailFailed: () -> Void
    @StateObject private var playbackController = VideoPlaybackController()
    @State private var thumbnail: CGImage?
    @State private var didFailThumbnail = false
    @State private var didReportThumbnailFailure = false
    @State private var photoPreviewItem: PhotoPreviewItem?
    @State private var documentPreviewItem: DocumentPreviewItem?
    @State private var isVideoPresented = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailContent
                .frame(height: 104)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(selectionBorder)

            if item.media.source == .statusStory {
                Image(systemName: "circle.dashed")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(5)
            }

            if isSelectionMode {
                selectionBadge
                    .padding(6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isSelectionMode && !isExportable ? 0.45 : 1)
        .onTapGesture {
            handleTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            handleTap()
        }
        .task(id: item.media.fileURL) {
            await loadThumbnailIfNeeded()
        }
        .sheet(item: $photoPreviewItem) { item in
            PhotoPreviewView(url: item.url)
        }
        #if os(iOS)
        .sheet(item: $documentPreviewItem) { item in
            DocumentPreviewView(url: item.url)
                .ignoresSafeArea()
        }
        #endif
        .sheet(isPresented: $isVideoPresented) {
            if let url = item.media.fileURL {
                VideoPlayerSheet(controller: playbackController, url: url)
            }
        }
    }

    private var isExportable: Bool {
        item.media.fileURL != nil && item.media.isFileAvailableInArchive
    }

    private var accessibilityLabel: String {
        isSelectionMode ? "Select media" : item.media.kind.placeholderText
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelectionMode && isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 3)
        }
    }

    private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3.weight(.semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.white)
            .background(.black.opacity(isSelected ? 0 : 0.45), in: Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if item.media.fileURL == nil || !item.media.isFileAvailableInArchive {
            Image(systemName: systemImageName)
                .font(.title2)
                .foregroundStyle(.secondary)
        } else if let thumbnail {
            Image(decorative: thumbnail, scale: 1, orientation: .up)
                .resizable()
                .scaledToFill()
        } else if didFailThumbnail {
            Image(systemName: systemImageName)
                .font(.title2)
                .foregroundStyle(.secondary)
        } else {
            ProgressView()
        }
    }

    private var systemImageName: String {
        switch item.media.kind {
        case .photo:
            return "photo"
        case .video, .videoMessage:
            return "video"
        case .audio, .voiceMessage:
            return "waveform"
        case .document:
            return "doc"
        default:
            return "paperclip"
        }
    }

    private func openPreview() {
        guard let url = item.media.fileURL else { return }
        switch item.media.kind {
        case .photo, .sticker:
            photoPreviewItem = PhotoPreviewItem(url: url)
        case .video, .videoMessage:
            playbackController.load(url: url, restart: true)
            isVideoPresented = true
        case .document:
            documentPreviewItem = DocumentPreviewItem(url: url)
        default:
            break
        }
    }

    private func handleTap() {
        if isSelectionMode {
            onToggleSelection()
        } else if item.media.fileURL != nil {
            openPreview()
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard thumbnail == nil, !didFailThumbnail, let url = item.media.fileURL else {
            return
        }

        let loadedThumbnail: CGImage?
        switch item.media.kind {
        case .photo, .sticker:
            loadedThumbnail = await Task.detached(priority: .utility) {
                downsampleImage(at: url, maxPixelSize: 360)
            }.value
        case .video, .videoMessage:
            loadedThumbnail = await videoThumbnail(at: url, maxPixelSize: 360)
        default:
            loadedThumbnail = nil
        }

        if let loadedThumbnail {
            thumbnail = loadedThumbnail
        } else {
            didFailThumbnail = true
            if !didReportThumbnailFailure {
                didReportThumbnailFailure = true
                onThumbnailFailed()
            }
        }
    }
}

private extension MessageRow {
    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let labels = [
            displayText,
            nonTextPlaceholderText,
            friendlySenderName,
            safeSenderPhoneNumber
        ]
            .compactMap { $0 }
            + (media?.searchableAttachmentLabels ?? [])

        return labels
        .filter { !$0.isEmpty }
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
    private var durationLoadTask: Task<Void, Never>?
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
        durationLoadTask = Task { [weak self, weak item] in
            guard let item else { return }
            guard let duration = await audioDuration(for: item.asset) else { return }
            await MainActor.run {
                guard self?.player?.currentItem === item else { return }
                self?.durationSeconds = duration
            }
        }
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
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
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
        durationLoadTask?.cancel()
        durationLoadTask = nil
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

        if let item {
            let duration = item.duration.seconds
            if duration.isFinite, duration > 0 {
                durationSeconds = duration
            }
        }

        if let durationSeconds, durationSeconds > 0 {
            currentTimeSeconds = min(max(0, currentTime), durationSeconds)
        } else {
            currentTimeSeconds = max(0, currentTime)
        }
    }
}

private struct MessageBubbleView: View {
    let message: MessageRow
    let isGroupChat: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var audioPlayback: AudioPlaybackController

    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 36)
            }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
                VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 5) {
                    if let senderLabel {
                        Text(senderLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(senderNameColor)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    MessageContentView(message: message)
                        .foregroundStyle(bubblePalette.primaryText)
                        .tint(bubblePalette.linkText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubblePalette.background, in: bubbleShape)
                .textSelection(.enabled)

                if let messageDate = message.messageDate {
                    Text(Self.dateFormatter.string(from: messageDate))
                        .font(.caption2)
                        .foregroundStyle(bubblePalette.metadataText)
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
        if message.isFromMe, isGroupChat {
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

    private var senderNameColor: Color {
        if message.isFromMe {
            return bubblePalette.sentSenderNameText
        }

        let seed = message.senderJID ?? message.friendlySenderName ?? message.safeSenderPhoneNumber ?? "unknown"
        return bubblePalette.groupSenderNameText(seed: seed)
    }

    private var bubblePalette: ChatBubblePalette {
        ChatBubblePalette(isFromMe: message.isFromMe, colorScheme: colorScheme)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: message.isFromMe ? 18 : 5,
            bottomTrailingRadius: message.isFromMe ? 5 : 18,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ChatBubblePalette {
    let isFromMe: Bool
    let colorScheme: ColorScheme

    var background: Color {
        guard colorScheme == .dark else {
            return isFromMe
                ? Color(red: 0.86, green: 0.95, blue: 0.84)
                : Color.white.opacity(0.94)
        }

        return isFromMe
            ? Color(red: 0.00, green: 0.36, blue: 0.30)
            : Color(red: 0.12, green: 0.17, blue: 0.20)
    }

    var primaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color.primary
    }

    var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.68) : Color.secondary
    }

    var metadataText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.secondary
    }

    var sentSenderNameText: Color {
        colorScheme == .dark
            ? Color(red: 0.77, green: 1.00, blue: 0.76)
            : Color(red: 0.10, green: 0.44, blue: 0.15)
    }

    var linkText: Color {
        colorScheme == .dark ? Color(red: 0.49, green: 0.79, blue: 1.00) : Color.accentColor
    }

    func groupSenderNameText(seed: String) -> Color {
        let palette: [Color]
        if colorScheme == .dark {
            palette = [
                Color(red: 0.49, green: 0.79, blue: 1.00),
                Color(red: 1.00, green: 0.74, blue: 0.42),
                Color(red: 0.96, green: 0.62, blue: 0.84),
                Color(red: 0.59, green: 0.88, blue: 0.70),
                Color(red: 0.82, green: 0.73, blue: 1.00)
            ]
        } else {
            palette = [
                Color(red: 0.02, green: 0.37, blue: 0.73),
                Color(red: 0.64, green: 0.25, blue: 0.00),
                Color(red: 0.62, green: 0.18, blue: 0.47),
                Color(red: 0.08, green: 0.42, blue: 0.25),
                Color(red: 0.42, green: 0.28, blue: 0.75)
            ]
        }

        let hash = seed.unicodeScalars.reduce(UInt64(5381)) { partialHash, scalar in
            ((partialHash << 5) &+ partialHash) &+ UInt64(scalar.value)
        }
        let index = Int(hash % UInt64(palette.count))
        return palette[index]
    }

    static func attachmentBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.secondary.opacity(0.08)
    }

    static func subtleIconBackground(isFromMe: Bool, colorScheme: ColorScheme) -> Color {
        guard colorScheme == .dark else {
            return isFromMe
                ? Color(red: 0.22, green: 0.55, blue: 0.24).opacity(0.16)
                : Color.secondary.opacity(0.12)
        }

        return Color.white.opacity(isFromMe ? 0.16 : 0.10)
    }

    static func subtleIconForeground(isFromMe: Bool, colorScheme: ColorScheme) -> Color {
        guard colorScheme == .dark else {
            return isFromMe
                ? Color(red: 0.12, green: 0.43, blue: 0.16)
                : Color.secondary
        }

        return Color.white.opacity(isFromMe ? 0.90 : 0.74)
    }
}

private struct MessageContentView: View {
    let message: MessageRow

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 6) {
            if let media = message.media, shouldShowAttachment(for: media) {
                attachmentView(for: media)
            } else if let displayText, let url = MessageLinkDetector.firstWebURL(in: displayText) {
                LinkPreviewAttachmentView(media: nil, fallbackURL: url)
            }

            if let media = message.media, isCaptionedAttachment(media), let displayText {
                LinkedMessageText(text: displayText)
                    .textSelection(.enabled)
            } else if let displayText {
                LinkedMessageText(text: displayText)
                    .textSelection(.enabled)
            } else if message.media == nil && message.isVoiceCallEvent {
                VoiceCallAttachmentView(isFromMe: message.isFromMe)
            } else if message.media == nil {
                Text(message.nonTextPlaceholderText ?? "Unsupported message")
                    .textSelection(.enabled)
            }
        }
    }

    private var displayText: String? {
        message.displayText ?? message.media?.fallbackCaptionText
    }

    private func shouldShowAttachment(for media: MediaMetadata) -> Bool {
        switch media.kind {
        case .photo, .video, .videoMessage, .audio, .voiceMessage, .document, .linkPreview:
            return true
        case .contact, .location, .sticker, .call, .callOrSystem, .system, .deleted, .media:
            return displayText == nil
        }
    }

    private func isCaptionedAttachment(_ media: MediaMetadata) -> Bool {
        switch media.kind {
        case .photo, .video, .videoMessage, .audio, .voiceMessage, .document:
            return true
        case .contact, .location, .sticker, .linkPreview, .call, .callOrSystem, .system, .deleted, .media:
            return false
        }
    }

    @ViewBuilder
    private func attachmentView(for media: MediaMetadata) -> some View {
        switch media.kind {
        case .photo:
            PhotoAttachmentView(media: media)
        case .video, .videoMessage:
            VideoAttachmentView(media: media)
        case .audio, .voiceMessage:
            AudioAttachmentView(messageID: message.id, media: media)
        case .contact:
            ContactAttachmentView(media: media)
        case .document:
            DocumentAttachmentView(media: media)
        case .linkPreview:
            LinkPreviewAttachmentView(media: media, fallbackURL: displayText.flatMap(MessageLinkDetector.firstWebURL(in:)))
        case .call:
            VoiceCallAttachmentView(isFromMe: message.isFromMe)
        default:
            Text(media.kind.placeholderText)
                .textSelection(.enabled)
        }
    }
}

private struct VoiceCallAttachmentView: View {
    let isFromMe: Bool
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var iconContainerSize: CGFloat = 30
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(iconBackground)

                Image(systemName: "phone.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(iconForeground)
                    .accessibilityHidden(true)
            }
            .frame(width: iconContainerSize, height: iconContainerSize)

            Text("Voice call")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .textSelection(.enabled)
        }
        .frame(maxWidth: 240, alignment: isFromMe ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice call")
    }

    private var iconBackground: Color {
        ChatBubblePalette.subtleIconBackground(isFromMe: isFromMe, colorScheme: colorScheme)
    }

    private var iconForeground: Color {
        ChatBubblePalette.subtleIconForeground(isFromMe: isFromMe, colorScheme: colorScheme)
    }
}

private struct LinkedMessageText: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(text)

        for match in MessageLinkDetector.webLinks(in: text) {
            guard let range = Range(match.range, in: text),
                  let attributedRange = Range(range, in: attributed) else {
                continue
            }
            attributed[attributedRange].link = match.url
            attributed[attributedRange].foregroundColor = linkColor
        }

        return attributed
    }

    private var linkColor: Color {
        ChatBubblePalette(isFromMe: false, colorScheme: colorScheme).linkText
    }
}

private struct LinkPreviewAttachmentView: View {
    let media: MediaMetadata?
    let fallbackURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    private var previewURL: URL? {
        media?.linkPreviewURL
            ?? fallbackURL
            ?? MessageLinkDetector.firstWebURL(in: media?.title)
    }

    private var title: String {
        guard let mediaTitle = media?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !mediaTitle.isEmpty,
              MediaMetadata.normalizedWebURL(from: mediaTitle) == nil else {
            return previewURL?.host(percentEncoded: false) ?? "Link"
        }
        return mediaTitle
    }

    private var subtitle: String {
        previewURL?.host(percentEncoded: false) ?? previewURL?.absoluteString ?? "Link preview"
    }

    var body: some View {
        if let previewURL {
            Link(destination: previewURL) {
                previewCard
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open link preview")
        } else {
            previewCard
        }
    }

    private var previewCard: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.72))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "link")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 260, alignment: .leading)
        .padding(10)
        .background(ChatBubblePalette.attachmentBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum MessageLinkDetector {
    struct Match {
        let range: NSRange
        let url: URL
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func firstWebURL(in text: String?) -> URL? {
        webLinks(in: text).first?.url
    }

    static func webLinks(in text: String?) -> [Match] {
        guard let text, !text.isEmpty, let detector else {
            return []
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector
            .matches(in: text, options: [], range: fullRange)
            .compactMap { result in
                guard let url = MediaMetadata.normalizedWebURL(from: result.url?.absoluteString) else {
                    return nil
                }
                return Match(range: result.range, url: url)
            }
    }
}

private struct ContactAttachmentView: View {
    let media: MediaMetadata
    @Environment(\.colorScheme) private var colorScheme

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
        .background(ChatBubblePalette.attachmentBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct DocumentAttachmentView: View {
    let media: MediaMetadata
    @Environment(\.colorScheme) private var colorScheme
    @State private var previewItem: DocumentPreviewItem?

    private var fileSizeText: String? {
        guard let fileSize = media.fileSize, fileSize > 0 else { return nil }
        return Self.fileSizeFormatter.string(fromByteCount: fileSize)
    }

    private var metadataText: String {
        [media.documentTypeLabel, fileSizeText]
            .compactMap { $0 }
            .joined(separator: " • ")
    }

    var body: some View {
        if !media.isFileAvailableInArchive || media.fileURL == nil {
            AttachmentPlaceholderView(title: "Document unavailable", systemImage: "doc")
        } else if let url = media.fileURL {
            HStack(spacing: 8) {
                Button {
                    previewItem = DocumentPreviewItem(url: url)
                } label: {
                    documentCard
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open document attachment")

                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share document")
            }
            .frame(maxWidth: 280, alignment: .leading)
            #if os(iOS)
            .sheet(item: $previewItem) { item in
                DocumentPreviewView(url: item.url)
                    .ignoresSafeArea()
            }
            #endif
        } else {
            AttachmentPlaceholderView(title: "Document unavailable", systemImage: "doc")
        }
    }

    private var documentCard: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))

                Image(systemName: documentIconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(media.documentDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(ChatBubblePalette.attachmentBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var documentIconName: String {
        switch media.fileExtensionLabel {
        case "pdf":
            return "doc.richtext"
        case "zip":
            return "doc.zipper"
        default:
            return "doc"
        }
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}

private struct DocumentPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
private struct DocumentPreviewView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif

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
                AttachmentPlaceholderView(title: unavailableTitle, systemImage: "video")
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
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipShape(previewShape)
                    .accessibilityLabel(accessibilityLabel)
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

    private var isVideoMessage: Bool {
        media.kind == .videoMessage
    }

    private var previewSize: CGSize {
        isVideoMessage ? CGSize(width: 184, height: 184) : CGSize(width: 260, height: 160)
    }

    private var previewShape: AnyShape {
        isVideoMessage
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var accessibilityLabel: String {
        isVideoMessage ? "Video message" : "Video attachment"
    }

    private var unavailableTitle: String {
        isVideoMessage ? "Video message unavailable" : "Video unavailable"
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
    @State private var fileDurationSeconds: Double?

    var body: some View {
        if !media.isFileAvailableInArchive || media.fileURL == nil {
            AttachmentPlaceholderView(title: "Audio unavailable", systemImage: "waveform")
        } else if let url = media.fileURL {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Button {
                        audioPlayback.toggle(messageID: messageID, url: url)
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

                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share audio")
                }

                Slider(
                    value: Binding(
                        get: { scrubberDisplayValue },
                        set: { scrubberValue = min(max($0, 0), scrubberDuration) }
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
            .task(id: url) {
                await loadFileDuration(from: url)
            }
        } else {
            AttachmentPlaceholderView(title: "Audio unavailable", systemImage: "waveform")
        }
    }

    private var currentTimeSeconds: Double {
        guard audioPlayback.isPlaying(messageID) || audioPlayback.pausedMessageID == messageID else {
            return 0
        }
        return audioPlayback.currentTimeSeconds
    }

    private var scrubberDuration: Double {
        let duration = (audioPlayback.isPlaying(messageID) || audioPlayback.pausedMessageID == messageID)
            ? (audioPlayback.durationSeconds ?? fileDurationSeconds ?? media.durationSeconds ?? 0)
            : (fileDurationSeconds ?? media.durationSeconds ?? 0)
        return max(duration, 0)
    }

    private var scrubberDisplayValue: Double {
        if isScrubbing {
            return min(scrubberValue, scrubberDuration)
        }
        let value = (audioPlayback.isPlaying(messageID) || audioPlayback.pausedMessageID == messageID)
            ? audioPlayback.currentTimeSeconds
            : 0
        return min(max(value, 0), scrubberDuration)
    }

    private func handleScrubEditingChanged(_ editing: Bool) {
        isScrubbing = editing
        guard !editing else { return }
        if let url = media.fileURL, !audioPlayback.isPlaying(messageID) {
            audioPlayback.toggle(messageID: messageID, url: url)
        }
        audioPlayback.seek(messageID: messageID, to: scrubberValue)
    }

    private func loadFileDuration(from url: URL) async {
        guard fileDurationSeconds == nil else { return }
        fileDurationSeconds = await audioDuration(at: url)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.subheadline)
        .foregroundStyle(ChatBubblePalette(isFromMe: false, colorScheme: colorScheme).secondaryText)
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

private func audioDuration(at url: URL) async -> Double? {
    await audioDuration(for: AVURLAsset(url: url))
}

private func audioDuration(for asset: AVAsset) async -> Double? {
    guard let duration = try? await asset.load(.duration) else {
        return nil
    }
    let seconds = duration.seconds
    return seconds.isFinite && seconds > 0 ? seconds : nil
}

private func prepareMediaPlaybackSession() {
    #if os(iOS)
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    try? AVAudioSession.sharedInstance().setActive(true)
    #endif
}

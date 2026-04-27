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
    let wallpaperDarkURL: URL?
    let wallpaperTheme: ChatWallpaperTheme
    let onLoadOlderMessages: () -> Void
    @StateObject private var audioPlayback = AudioPlaybackController()
    @StateObject private var instantVideoPlaybackCoordinator = InstantVideoPlaybackCoordinator()
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
    private let topScrollSafeInset: CGFloat = 10
    private let bottomSearchSafeInset: CGFloat = 44
    private let bottomAnchorSpacerHeight: CGFloat = 0
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
            ChatWallpaperBackgroundView(
                wallpaperURL: wallpaperURL,
                wallpaperDarkURL: wallpaperDarkURL,
                wallpaperTheme: wallpaperTheme
            )

            ScrollViewReader { proxy in
                List {
                        if isSearchingMessages, displayedMessages.isEmpty {
                            noMessageSearchResults
                        } else {
                            olderPaginationStatus

                        ForEach(displayedMessages, id: \.element.id) { index, message in
                            MessageBubbleView(
                                message: message,
                                isGroupChat: chat.isGroupChat,
                                showSenderAvatar: shouldShowSenderAvatar(at: index)
                            )
                                .environmentObject(audioPlayback)
                                .environmentObject(instantVideoPlaybackCoordinator)
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
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear
                        .frame(height: topScrollSafeInset)
                        .allowsHitTesting(false)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: effectiveBottomSearchSafeInset)
                        .allowsHitTesting(false)
                }
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
            .frame(height: bottomAnchorSpacerHeight)
            .id(bottomSpacerID)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
    }

    private var effectiveBottomSearchSafeInset: CGFloat {
        max(0, bottomSearchSafeInset - systemBottomSafeAreaInset)
    }

    private var systemBottomSafeAreaInset: CGFloat {
        #if os(iOS)
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .compactMap({ $0.windows.first(where: { $0.isKeyWindow }) })
            .first
        return keyWindow?.safeAreaInsets.bottom ?? 0
        #else
        return 0
        #endif
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

    private func shouldShowSenderAvatar(at index: Int) -> Bool {
        guard chat.isGroupChat else { return false }

        let currentMessage = displayedMessages[index].element
        guard !currentMessage.isFromMe else { return false }

        let nextIndex = index + 1
        guard nextIndex < displayedMessages.count else {
            return true
        }

        let nextMessage = displayedMessages[nextIndex].element
        return nextMessage.isFromMe || currentMessage.senderAvatarGroupingKey != nextMessage.senderAvatarGroupingKey
    }

    private func scrollToLatestMessageIfNeeded(using proxy: ScrollViewProxy, animated: Bool) {
        guard latestScrolledGeneration != initialMessageLoadGeneration else { return }
        latestScrolledGeneration = initialMessageLoadGeneration
        guard !messages.isEmpty else { return }
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
    let wallpaperDarkURL: URL?
    let wallpaperTheme: ChatWallpaperTheme
    @State private var image: CGImage?
    @State private var didFail = false
    @State private var loadedWallpaperURL: URL?

    var body: some View {
        ZStack {
            switch wallpaperTheme {
            case .archiveDefault:
                Color(.systemBackground)

                if let image {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.9)
                }
            case .plain:
                Color(.systemBackground)
            case .classic:
                ClassicDoodleWallpaperView()
            case .softPattern:
                ProceduralChatWallpaperView(theme: wallpaperTheme)
            case .demo:
                AssetChatWallpaperView(assetName: "WallpaperDemoArchive")
            }
        }
        .ignoresSafeArea()
        .task(id: wallpaperTaskID) {
            await loadWallpaperIfNeeded()
        }
    }

    private var resolvedWallpaperURL: URL? {
        guard wallpaperTheme == .archiveDefault else { return nil }
        if colorScheme == .dark {
            return wallpaperDarkURL ?? wallpaperURL
        }
        return wallpaperURL
    }

    private var wallpaperTaskID: String {
        [
            wallpaperTheme.rawValue,
            colorScheme == .dark ? "dark" : "light",
            wallpaperURL?.path ?? "none",
            wallpaperDarkURL?.path ?? "none"
        ].joined(separator: "|")
    }

    private func loadWallpaperIfNeeded() async {
        let wallpaperURL = resolvedWallpaperURL
        let cacheKey = wallpaperTaskID
        if loadedWallpaperURL != wallpaperURL {
            image = nil
            didFail = false
            loadedWallpaperURL = wallpaperURL
        }

        guard image == nil, !didFail, let wallpaperURL else {
            return
        }

        if let cachedImage = ChatWallpaperImageCache.shared.image(for: cacheKey) {
            image = cachedImage
            return
        }

        let loadedImage = await Task.detached(priority: .utility) {
            downsampleImage(at: wallpaperURL, maxPixelSize: 1400)
        }.value

        if let loadedImage {
            ChatWallpaperImageCache.shared.store(loadedImage, for: cacheKey)
            image = loadedImage
        } else {
            didFail = true
        }
    }
}

private final class ChatWallpaperImageCache {
    static let shared = ChatWallpaperImageCache()

    private let lock = NSLock()
    private var images: [String: CGImage] = [:]
    private let maxCount = 4

    func image(for key: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[key]
    }

    func store(_ image: CGImage, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if images.count >= maxCount, images[key] == nil {
            images.removeAll(keepingCapacity: true)
        }
        images[key] = image
    }
}

struct ClassicDoodleWallpaperView: View {
    var body: some View {
        AssetChatWallpaperView(assetName: "WallpaperClassicDoodles")
    }
}

struct AssetChatWallpaperView: View {
    let assetName: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemBackground)

                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
    }
}

struct ProceduralChatWallpaperView: View {
    @Environment(\.colorScheme) private var colorScheme
    let theme: ChatWallpaperTheme

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(palette.background)
            )

            switch theme {
            case .classic:
                drawClassicSymbols(in: &context, size: size)
            case .softPattern:
                drawDemoCompanionPattern(in: &context, size: size)
            case .demo:
                break
            case .archiveDefault, .plain:
                break
            }
        }
        .background(palette.background)
    }

    private var palette: WallpaperPalette {
        WallpaperPalette(theme: theme, isDark: colorScheme == .dark)
    }

    private func drawSoftPattern(in context: inout GraphicsContext, size: CGSize) {
        drawDots(in: &context, size: size)
        drawLines(in: &context, size: size)
        drawRings(in: &context, size: size)
    }

    private func drawDots(in context: inout GraphicsContext, size: CGSize) {
        let spacing = palette.dotSpacing
        var y = spacing * 0.6
        var row = 0

        while y < size.height + spacing {
            var x = spacing * (row.isMultiple(of: 2) ? 0.45 : 0.95)
            while x < size.width + spacing {
                let rect = CGRect(x: x, y: y, width: palette.dotSize, height: palette.dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(palette.dot))
                x += spacing
            }
            y += spacing
            row += 1
        }
    }

    private func drawLines(in context: inout GraphicsContext, size: CGSize) {
        guard palette.lineOpacity > 0 else { return }
        let spacing = palette.lineSpacing
        var x = -size.height

        while x < size.width + size.height {
            var path = Path()
            path.move(to: CGPoint(x: x, y: size.height))
            path.addLine(to: CGPoint(x: x + size.height, y: 0))
            context.stroke(
                path,
                with: .color(palette.line.opacity(palette.lineOpacity)),
                lineWidth: palette.lineWidth
            )
            x += spacing
        }
    }

    private func drawRings(in context: inout GraphicsContext, size: CGSize) {
        guard palette.ringOpacity > 0 else { return }
        let spacing = palette.ringSpacing
        var y = spacing * 0.75
        var row = 0

        while y < size.height + spacing {
            var x = spacing * (row.isMultiple(of: 2) ? 0.55 : 1.2)
            while x < size.width + spacing {
                let rect = CGRect(x: x, y: y, width: palette.ringSize, height: palette.ringSize)
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(palette.ring.opacity(palette.ringOpacity)),
                    lineWidth: palette.ringLineWidth
                )
                x += spacing
            }
            y += spacing * 1.08
            row += 1
        }
    }

    private func drawClassicSymbols(in context: inout GraphicsContext, size: CGSize) {
        drawFineTexture(in: &context, size: size)

        let spacing: CGFloat = 150
        var y: CGFloat = 90
        var row = 0

        while y < size.height + spacing {
            var x: CGFloat = 70 + CGFloat(row % 2) * 18
            var column = 0

            while x < size.width + spacing {
                let symbol = (row + column) % 4
                let center = CGPoint(x: x + CGFloat(symbol % 2) * 18, y: y + CGFloat(symbol / 2) * 18)
                drawClassicSymbol(symbol, center: center, in: &context)
                x += spacing
                column += 1
            }

            y += spacing
            row += 1
        }
    }

    private func drawClassicSymbol(_ symbol: Int, center: CGPoint, in context: inout GraphicsContext) {
        switch symbol {
        case 0:
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)),
                with: .color(palette.ring)
            )

            strokeLine(from: CGPoint(x: center.x + 22, y: center.y - 8), to: CGPoint(x: center.x + 54, y: center.y - 8), in: &context)
            strokeLine(from: CGPoint(x: center.x + 22, y: center.y + 8), to: CGPoint(x: center.x + 44, y: center.y + 8), in: &context)
        case 1:
            strokeLine(from: CGPoint(x: center.x - 22, y: center.y), to: CGPoint(x: center.x + 22, y: center.y), in: &context)
            strokeLine(from: CGPoint(x: center.x, y: center.y - 22), to: CGPoint(x: center.x, y: center.y + 22), in: &context)
        case 2:
            let outer = CGRect(x: center.x - 25, y: center.y - 13, width: 50, height: 26)
            let inner = CGRect(x: center.x - 18, y: center.y - 7, width: 36, height: 14)
            context.fill(Path(outer), with: .color(palette.line))
            context.fill(Path(inner), with: .color(palette.background))
        default:
            strokeLine(from: CGPoint(x: center.x - 22, y: center.y + 12), to: CGPoint(x: center.x, y: center.y - 14), in: &context)
            strokeLine(from: CGPoint(x: center.x, y: center.y - 14), to: CGPoint(x: center.x + 24, y: center.y + 12), in: &context)
        }
    }

    private func drawDemoCompanionPattern(in context: inout GraphicsContext, size: CGSize) {
        drawFineTexture(in: &context, size: size)

        let spacing: CGFloat = 178
        var y: CGFloat = 82
        var row = 0

        while y < size.height + spacing {
            var x: CGFloat = 46 + CGFloat(row % 3) * 22
            var column = 0

            while x < size.width + spacing {
                let symbol = (row * 2 + column) % 4
                let center = CGPoint(
                    x: x + CGFloat((symbol + row) % 2) * 20,
                    y: y + CGFloat((symbol + column) % 2) * 16
                )
                drawClassicSymbol(symbol, center: center, in: &context)
                x += spacing
                column += 1
            }

            y += spacing * 0.92
            row += 1
        }
    }

    private func drawFineTexture(in context: inout GraphicsContext, size: CGSize) {
        guard palette.lineOpacity > 0 else { return }
        var y: CGFloat = 0

        while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y + 8))
            context.stroke(
                path,
                with: .color(palette.line.opacity(palette.lineOpacity * 0.36)),
                lineWidth: 0.5
            )
            y += 10
        }
    }

    private func strokeLine(from start: CGPoint, to end: CGPoint, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(palette.line), lineWidth: palette.lineWidth)
    }
}

private struct WallpaperPalette {
    let background: Color
    let dot: Color
    let line: Color
    let ring: Color
    let dotSpacing: CGFloat
    let dotSize: CGFloat
    let lineSpacing: CGFloat
    let lineWidth: CGFloat
    let lineOpacity: Double
    let ringSpacing: CGFloat
    let ringSize: CGFloat
    let ringLineWidth: CGFloat
    let ringOpacity: Double

    init(theme: ChatWallpaperTheme, isDark: Bool) {
        switch (theme, isDark) {
        case (.classic, false):
            background = Color(red: 0.957, green: 0.937, blue: 0.898)
            dot = Color(red: 0.965, green: 0.945, blue: 0.910)
            line = Color(red: 0.776, green: 0.824, blue: 0.792).opacity(0.72)
            ring = Color(red: 0.839, green: 0.863, blue: 0.827).opacity(0.78)
            dotSpacing = 34
            dotSize = 2.5
            lineSpacing = 96
            lineWidth = 3
            lineOpacity = 0.08
            ringSpacing = 118
            ringSize = 16
            ringLineWidth = 1
            ringOpacity = 0.08
        case (.classic, true):
            background = Color(red: 0.071, green: 0.106, blue: 0.122)
            dot = Color(red: 0.075, green: 0.118, blue: 0.134)
            line = Color(red: 0.220, green: 0.300, blue: 0.330).opacity(0.70)
            ring = Color(red: 0.160, green: 0.230, blue: 0.255).opacity(0.74)
            dotSpacing = 34
            dotSize = 2.5
            lineSpacing = 96
            lineWidth = 3
            lineOpacity = 0.09
            ringSpacing = 118
            ringSize = 16
            ringLineWidth = 1
            ringOpacity = 0.07
        case (.softPattern, false):
            background = Color(red: 0.935, green: 0.913, blue: 0.842)
            dot = Color(red: 0.955, green: 0.932, blue: 0.860)
            line = Color(red: 0.690, green: 0.750, blue: 0.705).opacity(0.66)
            ring = Color(red: 0.808, green: 0.690, blue: 0.470).opacity(0.62)
            dotSpacing = 42
            dotSize = 3
            lineSpacing = 120
            lineWidth = 3
            lineOpacity = 0.06
            ringSpacing = 104
            ringSize = 14
            ringLineWidth = 1
            ringOpacity = 0.08
        case (.softPattern, true):
            background = Color(red: 0.105, green: 0.122, blue: 0.112)
            dot = Color(red: 0.125, green: 0.145, blue: 0.132)
            line = Color(red: 0.255, green: 0.335, blue: 0.300).opacity(0.64)
            ring = Color(red: 0.430, green: 0.345, blue: 0.215).opacity(0.62)
            dotSpacing = 42
            dotSize = 3
            lineSpacing = 120
            lineWidth = 3
            lineOpacity = 0.04
            ringSpacing = 104
            ringSize = 14
            ringLineWidth = 1
            ringOpacity = 0.07
        default:
            background = Color(.systemBackground)
            dot = .clear
            line = .clear
            ring = .clear
            dotSpacing = 1
            dotSize = 0
            lineSpacing = 1
            lineWidth = 0
            lineOpacity = 0
            ringSpacing = 1
            ringSize = 0
            ringLineWidth = 0
            ringOpacity = 0
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
    @State private var selectionDragAnchorID: String?
    @State private var mediaDisplayLimit = 120
    @State private var isLoadingMedia = false
    @State private var mediaBrowserSelection: MediaBrowserSelection?
    @State private var mediaViewportHeight: CGFloat = 0
    @State private var selectionAutoScrollDirection: MediaSelectionAutoScrollDirection?
    @State private var selectionAutoScrollLocation: CGPoint?
    @State private var selectionAutoScrollTask: Task<Void, Never>?
    @State private var lastSelectionDragLocation: CGPoint?
    #if os(iOS)
    @State private var mediaScrollView: UIScrollView?
    #endif

    private let mediaPageSize = 120
    private let selectionAutoScrollEdgeInset: CGFloat = 76
    private let selectionAutoScrollStep = 1
    private let selectionAutoScrollInterval: UInt64 = 16_666_667
    private let selectionAutoScrollMaxPointsPerTick: CGFloat = 12
    private let selectionDragHitRadius: CGFloat = 14

    private var mediaTaskID: String {
        "\(chat.id)-\(selectedFilter.rawValue)-\(mediaDisplayLimit)"
    }

    private var exportableMediaItems: [ChatMediaItem] {
        mediaItems.filter(isExportableMediaItem)
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

    private var previewableMediaItems: [ChatMediaItem] {
        mediaItems.filter(isPreviewableMediaItem)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            chatDetailsSection
                            mediaGallerySection(scrollProxy: scrollProxy)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                    }
                    #if os(iOS)
                    .background(
                        MediaScrollViewAccessor { scrollView in
                            mediaScrollView = scrollView
                            if selectionDragIntent == .selecting {
                                scrollView?.isScrollEnabled = false
                            }
                        }
                    )
                    #endif
                    .coordinateSpace(name: "chatInfoMediaGrid")
                    .onAppear {
                        mediaViewportHeight = geometry.size.height
                    }
                    .onChange(of: geometry.size.height) { _, newHeight in
                        mediaViewportHeight = newHeight
                    }
                }
            }
            .navigationTitle(chat.classification == .statusStoryFragment ? "Stories" : "Chat Info")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSelectingMedia ? "Cancel" : "Done") {
                        if isSelectingMedia {
                            setMediaSelectionMode(false)
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    if isSelectingMedia {
                        Text(selectionSummaryText)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isSelectingMedia {
                        Button {
                            shareSelectedMedia()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(selectedExportURLs.isEmpty)
                        .accessibilityLabel("Share selected media")
                    } else {
                        Button("Select") {
                            setMediaSelectionMode(true)
                        }
                        .disabled(exportableMediaItems.isEmpty)
                    }
                }
            }
            .task(id: mediaTaskID) {
                loadMediaItems()
            }
            .onChange(of: selectedFilter) { _, _ in
                resetMediaPaging()
            }
            .onDisappear {
                resetSelectionDrag()
            }
            #if os(iOS)
            .sheet(item: $mediaShareSelection) { selection in
                ActivityView(activityItems: selection.urls)
            }
            #endif
            .sheet(item: $mediaBrowserSelection) { selection in
                ChatInfoMediaBrowserView(items: selection.items, initialItemID: selection.initialItemID)
            }
        }
    }

    private var chatDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Title", value: chat.title)
            LabeledContent("Messages", value: chat.messageCount.formatted())
            if chat.classification == .statusStoryFragment {
                LabeledContent("Type", value: "Stories")
            }
        }
        .font(.subheadline)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func mediaGallerySection(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Media")
                .font(.headline)

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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                if let summaryText {
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                mediaSelectionControls

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 92), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(mediaItems) { item in
                        ChatInfoMediaTile(
                            item: item,
                            isSelectionMode: isSelectingMedia,
                            isSelected: selectedMediaIDs.contains(item.id),
                            onToggleSelection: {
                                toggleMediaSelection(item)
                            },
                            onOpen: {
                                presentMediaBrowser(startingAt: item)
                            }
                        ) {
                            thumbnailFailureIDs.insert(item.id)
                        }
                        .id(item.id)
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
                .onPreferenceChange(ChatInfoMediaTileFramePreferenceKey.self) { frames in
                    mediaTileFrames = frames
                }
                .mediaSelectionDrag(
                    isSelectingMedia,
                    gesture: mediaSelectionDragGesture(scrollProxy: scrollProxy)
                )

                if canLoadMoreMedia {
                    mediaLoadingSentinel
                }
            }
        }
    }

    @ViewBuilder
    private var mediaSelectionControls: some View {
        HStack(spacing: 10) {
            Label(isSelectingMedia ? selectionSummaryText : exportableSummaryText, systemImage: isSelectingMedia ? "checkmark.circle" : "photo.stack")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.10), in: Capsule())

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
        }
    }

    private func compactMediaButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 38, height: 34)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var summaryText: String? {
        guard let mediaSummary else { return nil }
        var parts = ["Showing \(mediaSummary.displayedRows.formatted()) items"]
        if canLoadMoreMedia {
            parts.append("more available")
        }
        if mediaSummary.missingOrUnresolvedRows > 0 {
            parts.append("\(mediaSummary.missingOrUnresolvedRows.formatted()) unavailable")
        }
        if !thumbnailFailureIDs.isEmpty {
            parts.append("\(thumbnailFailureIDs.count.formatted()) thumbnail failed")
        }
        return parts.joined(separator: " • ")
    }

    private func loadMediaItems() {
        guard !isLoadingMedia else { return }
        isLoadingMedia = true
        defer { isLoadingMedia = false }

        do {
            let page = try store.mediaLibraryPage(for: chat, filter: selectedFilter, limit: mediaDisplayLimit)
            mediaItems = page.items
            mediaSummary = page.summary
            thumbnailFailureIDs = []
            selectedMediaIDs = selectedMediaIDs.intersection(Set(page.items.map(\.id)))
            if page.items.isEmpty {
                setMediaSelectionMode(false)
            }
            mediaLoadError = nil
            logMediaSummary(page.summary)
        } catch {
            mediaItems = []
            mediaSummary = nil
            thumbnailFailureIDs = []
            selectedMediaIDs = []
            setMediaSelectionMode(false)
            mediaLoadError = "Could not load media."
        }
    }

    private var canLoadMoreMedia: Bool {
        guard let mediaSummary else { return false }
        return mediaItems.count >= mediaDisplayLimit
            || mediaSummary.queryCapMayHideRows
            || mediaSummary.totalRowsMatchingFilter > mediaSummary.rowsScanned
    }

    private var mediaLoadingSentinel: some View {
        HStack(spacing: 8) {
            if isLoadingMedia {
                ProgressView()
                    .controlSize(.small)
            }

            Text(isLoadingMedia ? "Loading more media" : "More media")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .onAppear {
            loadNextMediaPageIfNeeded()
        }
    }

    private func loadNextMediaPageIfNeeded() {
        guard canLoadMoreMedia, !isLoadingMedia else { return }
        mediaDisplayLimit += mediaPageSize
    }

    private func resetMediaPaging() {
        mediaDisplayLimit = mediaPageSize
        mediaTileFrames = [:]
        resetSelectionDrag()
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
        guard isExportableMediaItem(item) else {
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

    private func setMediaSelectionMode(_ isEnabled: Bool) {
        isSelectingMedia = isEnabled
        resetSelectionDrag()
        if !isEnabled {
            selectedMediaIDs = []
        }
    }

    private func mediaSelectionDragGesture(scrollProxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("chatInfoMediaGrid"))
            .onChanged { value in
                guard isSelectingMedia else { return }
                guard beginSelectionDragIfNeeded(value) else { return }
                if lastSelectionDragLocation == nil {
                    updateSelectionDrag(at: value.startLocation, scrollProxy: scrollProxy)
                }
                updateSelectionDrag(at: value.location, scrollProxy: scrollProxy)
            }
            .onEnded { _ in
                resetSelectionDrag()
            }
    }

    private func beginSelectionDragIfNeeded(_ value: DragGesture.Value) -> Bool {
        if let selectionDragIntent {
            return selectionDragIntent == .selecting
        }

        guard let startItem = exportableItem(at: value.startLocation) else {
            selectionDragIntent = .scrolling
            setMediaScrollEnabled(true)
            return false
        }

        selectionDragIntent = .selecting
        selectionDragAnchorID = startItem.id
        selectionDragMode = selectedMediaIDs.contains(startItem.id) ? .remove : .add
        setMediaScrollEnabled(false)
        return true
    }

    private func updateSelectionDrag(at location: CGPoint, scrollProxy: ScrollViewProxy) {
        updateSelectionAutoScrollDirection(for: location, scrollProxy: scrollProxy)

        let items = selectionItems(hitBy: location, previousLocation: lastSelectionDragLocation)
        lastSelectionDragLocation = location

        for item in items where !selectionDragVisitedIDs.contains(item.id) {
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
    }

    private func updateSelectionAutoScrollDirection(for location: CGPoint, scrollProxy: ScrollViewProxy) {
        let viewportHeight = currentMediaViewportHeight
        guard isSelectingMedia, viewportHeight > 0 else {
            selectionAutoScrollDirection = nil
            selectionAutoScrollLocation = nil
            stopSelectionAutoScroll()
            return
        }

        selectionAutoScrollLocation = location

        let newDirection: MediaSelectionAutoScrollDirection?
        if location.y > viewportHeight - selectionAutoScrollEdgeInset {
            newDirection = .down
        } else if location.y < selectionAutoScrollEdgeInset {
            newDirection = .up
        } else {
            newDirection = nil
        }

        guard newDirection != selectionAutoScrollDirection else {
            if newDirection != nil, selectionAutoScrollTask == nil {
                startSelectionAutoScroll(scrollProxy: scrollProxy)
            }
            return
        }
        selectionAutoScrollDirection = newDirection

        if newDirection == nil {
            stopSelectionAutoScroll()
        } else {
            startSelectionAutoScroll(scrollProxy: scrollProxy)
        }
    }

    private var currentMediaViewportHeight: CGFloat {
        #if os(iOS)
        if let mediaScrollView, mediaScrollView.bounds.height > 0 {
            return mediaScrollView.bounds.height
        }
        #endif
        return mediaViewportHeight
    }

    private func startSelectionAutoScroll(scrollProxy: ScrollViewProxy) {
        guard selectionAutoScrollTask == nil else { return }
        selectionAutoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: selectionAutoScrollInterval)
                guard !Task.isCancelled, isSelectingMedia, let direction = selectionAutoScrollDirection else { break }

                scrollSelection(direction: direction, scrollProxy: scrollProxy)
                if let location = selectionAutoScrollLocation {
                    updateSelectionDrag(at: location, scrollProxy: scrollProxy)
                }
            }
        }
    }

    private func stopSelectionAutoScroll() {
        selectionAutoScrollTask?.cancel()
        selectionAutoScrollTask = nil
    }

    private func scrollSelection(
        direction: MediaSelectionAutoScrollDirection,
        scrollProxy: ScrollViewProxy
    ) {
        #if os(iOS)
        if let mediaScrollView {
            scrollSelectionSmoothly(direction: direction, scrollView: mediaScrollView)
            return
        }
        #endif

        let indexedFrames = mediaItems.enumerated().compactMap { index, item -> (index: Int, item: ChatMediaItem, frame: CGRect)? in
            guard let frame = mediaTileFrames[item.id] else { return nil }
            return (index, item, frame)
        }

        guard !indexedFrames.isEmpty else { return }

        let visibleFrames = indexedFrames.filter { entry in
            entry.frame.maxY >= 0 && entry.frame.minY <= mediaViewportHeight
        }
        let referenceFrames = visibleFrames.isEmpty ? indexedFrames : visibleFrames

        switch direction {
        case .down:
            guard let currentIndex = referenceFrames.max(by: { $0.frame.maxY < $1.frame.maxY })?.index else { return }
            let targetIndex = min(currentIndex + selectionAutoScrollStep, mediaItems.count - 1)
            scrollProxy.scrollTo(mediaItems[targetIndex].id, anchor: .bottom)
            if targetIndex >= mediaItems.count - selectionAutoScrollStep {
                loadNextMediaPageIfNeeded()
            }
        case .up:
            guard let currentIndex = referenceFrames.min(by: { $0.frame.minY < $1.frame.minY })?.index else { return }
            let targetIndex = max(currentIndex - selectionAutoScrollStep, 0)
            scrollProxy.scrollTo(mediaItems[targetIndex].id, anchor: .top)
        }
    }

    #if os(iOS)
    private func scrollSelectionSmoothly(
        direction: MediaSelectionAutoScrollDirection,
        scrollView: UIScrollView
    ) {
        let viewportHeight = scrollView.bounds.height
        guard viewportHeight > 0 else { return }

        let locationY = selectionAutoScrollLocation?.y ?? viewportHeight / 2
        let edgeProgress: CGFloat
        switch direction {
        case .down:
            edgeProgress = min(max((locationY - (viewportHeight - selectionAutoScrollEdgeInset)) / selectionAutoScrollEdgeInset, 0), 1)
        case .up:
            edgeProgress = min(max((selectionAutoScrollEdgeInset - locationY) / selectionAutoScrollEdgeInset, 0), 1)
        }

        let delta = max(2, edgeProgress * selectionAutoScrollMaxPointsPerTick)
        let currentOffset = scrollView.contentOffset
        let maximumOffsetY = max(scrollView.contentSize.height - viewportHeight + scrollView.adjustedContentInset.bottom, -scrollView.adjustedContentInset.top)
        let proposedY: CGFloat
        switch direction {
        case .down:
            proposedY = min(currentOffset.y + delta, maximumOffsetY)
        case .up:
            proposedY = max(currentOffset.y - delta, -scrollView.adjustedContentInset.top)
        }

        guard abs(proposedY - currentOffset.y) >= 0.5 else {
            if direction == .down {
                loadNextMediaPageIfNeeded()
            }
            return
        }
        scrollView.setContentOffset(CGPoint(x: currentOffset.x, y: proposedY), animated: false)

        if direction == .down,
           scrollView.contentOffset.y + viewportHeight > scrollView.contentSize.height - 360 {
            loadNextMediaPageIfNeeded()
        }
    }
    #endif

    private func exportableItem(at location: CGPoint) -> ChatMediaItem? {
        mediaItems.first { item in
            isExportableMediaItem(item)
                && mediaTileFrames[item.id]?.contains(location) == true
        }
    }

    private func selectionItems(hitBy location: CGPoint, previousLocation: CGPoint?) -> [ChatMediaItem] {
        var hitItems = exportableItems(hitBy: location, previousLocation: previousLocation)
        if hitItems.isEmpty, let direction = selectionAutoScrollDirection, let edgeItem = edgeSelectionItem(for: direction) {
            hitItems = [edgeItem]
        }

        guard let anchorID = selectionDragAnchorID else {
            return hitItems
        }

        var items: [ChatMediaItem] = []
        var itemIDs = Set<String>()
        for hitItem in hitItems {
            for item in selectionRangeItems(from: anchorID, to: hitItem.id) where itemIDs.insert(item.id).inserted {
                items.append(item)
            }
        }
        return items
    }

    private func exportableItems(hitBy location: CGPoint, previousLocation: CGPoint?) -> [ChatMediaItem] {
        let previousLocation = previousLocation ?? location
        let segmentBounds = CGRect(
            x: min(previousLocation.x, location.x),
            y: min(previousLocation.y, location.y),
            width: abs(previousLocation.x - location.x),
            height: abs(previousLocation.y - location.y)
        )
        .standardized
        .insetBy(dx: -selectionDragHitRadius, dy: -selectionDragHitRadius)

        return mediaItems.filter { item in
            guard isExportableMediaItem(item),
                  let frame = mediaTileFrames[item.id]
            else {
                return false
            }
            guard frame.intersects(segmentBounds)
                || frame.insetBy(dx: -selectionDragHitRadius, dy: -selectionDragHitRadius).contains(location)
            else {
                return false
            }
            return dragSegment(from: previousLocation, to: location, intersects: frame, radius: selectionDragHitRadius)
        }
    }

    private func selectionRangeItems(from startID: String, to endID: String) -> [ChatMediaItem] {
        guard let startIndex = mediaItems.firstIndex(where: { $0.id == startID }),
              let endIndex = mediaItems.firstIndex(where: { $0.id == endID }) else {
            return []
        }

        let lowerBound = min(startIndex, endIndex)
        let upperBound = max(startIndex, endIndex)
        return mediaItems[lowerBound...upperBound].filter(isExportableMediaItem)
    }

    private func edgeSelectionItem(for direction: MediaSelectionAutoScrollDirection) -> ChatMediaItem? {
        let viewportHeight = currentMediaViewportHeight
        let visibleItems = mediaItems.enumerated().compactMap { index, item -> (index: Int, item: ChatMediaItem, frame: CGRect)? in
            guard isExportableMediaItem(item),
                  let frame = mediaTileFrames[item.id],
                  frame.maxY >= 0,
                  frame.minY <= viewportHeight else {
                return nil
            }
            return (index, item, frame)
        }

        switch direction {
        case .down:
            return visibleItems.max { lhs, rhs in
                if lhs.frame.maxY == rhs.frame.maxY {
                    return lhs.index < rhs.index
                }
                return lhs.frame.maxY < rhs.frame.maxY
            }?.item
        case .up:
            return visibleItems.min { lhs, rhs in
                if lhs.frame.minY == rhs.frame.minY {
                    return lhs.index < rhs.index
                }
                return lhs.frame.minY < rhs.frame.minY
            }?.item
        }
    }

    private func isExportableMediaItem(_ item: ChatMediaItem) -> Bool {
        item.media.fileURL != nil && item.media.isFileAvailableInArchive
    }

    private func dragSegment(from start: CGPoint, to end: CGPoint, intersects rect: CGRect, radius: CGFloat) -> Bool {
        let expandedRect = rect.insetBy(dx: -radius, dy: -radius)
        if expandedRect.contains(start) || expandedRect.contains(end) {
            return true
        }

        let corners = [
            CGPoint(x: expandedRect.minX, y: expandedRect.minY),
            CGPoint(x: expandedRect.maxX, y: expandedRect.minY),
            CGPoint(x: expandedRect.maxX, y: expandedRect.maxY),
            CGPoint(x: expandedRect.minX, y: expandedRect.maxY)
        ]

        let edges = [
            (corners[0], corners[1]),
            (corners[1], corners[2]),
            (corners[2], corners[3]),
            (corners[3], corners[0])
        ]

        return edges.contains { edgeStart, edgeEnd in
            lineSegmentsIntersect(start, end, edgeStart, edgeEnd)
        }
    }

    private func lineSegmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ q1: CGPoint, _ q2: CGPoint) -> Bool {
        func crossProduct(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }

        func contains(_ point: CGPoint, onSegmentFrom start: CGPoint, to end: CGPoint) -> Bool {
            point.x >= min(start.x, end.x) - 0.5
                && point.x <= max(start.x, end.x) + 0.5
                && point.y >= min(start.y, end.y) - 0.5
                && point.y <= max(start.y, end.y) + 0.5
        }

        let o1 = crossProduct(p1, p2, q1)
        let o2 = crossProduct(p1, p2, q2)
        let o3 = crossProduct(q1, q2, p1)
        let o4 = crossProduct(q1, q2, p2)
        let epsilon: CGFloat = 0.001

        if abs(o1) < epsilon, contains(q1, onSegmentFrom: p1, to: p2) { return true }
        if abs(o2) < epsilon, contains(q2, onSegmentFrom: p1, to: p2) { return true }
        if abs(o3) < epsilon, contains(p1, onSegmentFrom: q1, to: q2) { return true }
        if abs(o4) < epsilon, contains(p2, onSegmentFrom: q1, to: q2) { return true }

        return (o1 > 0) != (o2 > 0) && (o3 > 0) != (o4 > 0)
    }

    private func isPreviewableMediaItem(_ item: ChatMediaItem) -> Bool {
        guard item.media.fileURL != nil, item.media.isFileAvailableInArchive else {
            return false
        }

        switch item.media.kind {
        case .photo, .sticker, .video, .videoMessage, .document:
            return true
        default:
            return false
        }
    }

    private func presentMediaBrowser(startingAt item: ChatMediaItem) {
        guard isPreviewableMediaItem(item) else { return }
        mediaBrowserSelection = MediaBrowserSelection(items: previewableMediaItems, initialItemID: item.id)
    }

    private func resetSelectionDrag() {
        selectionDragMode = nil
        selectionDragVisitedIDs = []
        selectionDragIntent = nil
        selectionDragAnchorID = nil
        lastSelectionDragLocation = nil
        selectionAutoScrollDirection = nil
        selectionAutoScrollLocation = nil
        stopSelectionAutoScroll()
        setMediaScrollEnabled(true)
    }

    private func setMediaScrollEnabled(_ isEnabled: Bool) {
        #if os(iOS)
        mediaScrollView?.isScrollEnabled = isEnabled
        #endif
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

private struct MediaBrowserSelection: Identifiable {
    let id = UUID()
    let items: [ChatMediaItem]
    let initialItemID: String
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

private enum MediaSelectionAutoScrollDirection: Hashable {
    case up
    case down
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
private struct MediaScrollViewAccessor: UIViewRepresentable {
    let onResolve: (UIScrollView?) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            onResolve(view.enclosingScrollView)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            onResolve(uiView.enclosingScrollView)
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var view = superview
        while let currentView = view {
            if let scrollView = currentView as? UIScrollView {
                return scrollView
            }
            view = currentView.superview
        }
        return nil
    }
}

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
    let onOpen: () -> Void
    let onThumbnailFailed: () -> Void
    @State private var thumbnail: CGImage?
    @State private var didFailThumbnail = false
    @State private var didReportThumbnailFailure = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                thumbnailContent
                    .frame(width: proxy.size.width, height: proxy.size.width)
                    .clipped()
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(tileShape)
                    .overlay(selectionBorder)
            }
            .aspectRatio(1, contentMode: .fit)

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
        .frame(maxWidth: .infinity)
        .contentShape(tileShape)
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
    }

    private var isExportable: Bool {
        item.media.fileURL != nil && item.media.isFileAvailableInArchive
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    private var accessibilityLabel: String {
        isSelectionMode ? "Select media" : item.media.kind.placeholderText
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelectionMode && isSelected {
            tileShape
                .stroke(Color.accentColor, lineWidth: 3)
        } else {
            tileShape
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func handleTap() {
        if isSelectionMode {
            onToggleSelection()
        } else if isExportable {
            onOpen()
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
                downsampleImage(at: url, maxPixelSize: 260)
            }.value
        case .video, .videoMessage:
            loadedThumbnail = await videoThumbnail(at: url, maxPixelSize: 260)
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

private struct MediaViewerTopOverlay: View {
    let shareURL: URL?
    let closeAccessibilityLabel: String
    let shareAccessibilityLabel: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Button(action: onClose) {
                topControlImage(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeAccessibilityLabel)

            Spacer(minLength: 12)

            if let shareURL {
                ShareLink(item: shareURL) {
                    topControlImage(systemName: "square.and.arrow.up.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shareAccessibilityLabel)
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(alignment: .top) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.72),
                    Color.black.opacity(0.38),
                    Color.black.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private func topControlImage(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 32))
            .foregroundStyle(.white, .black.opacity(0.35))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

private struct ChatInfoMediaBrowserView: View {
    let items: [ChatMediaItem]
    let initialItemID: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItemID: String

    init(items: [ChatMediaItem], initialItemID: String) {
        self.items = items
        self.initialItemID = initialItemID
        _selectedItemID = State(initialValue: initialItemID)
    }

    private var selectedItem: ChatMediaItem? {
        items.first { $0.id == selectedItemID } ?? items.first
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $selectedItemID) {
                ForEach(items) { item in
                    ChatInfoMediaBrowserPage(item: item)
                        .tag(item.id)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            #endif
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            MediaViewerTopOverlay(
                shareURL: selectedItem?.media.fileURL,
                closeAccessibilityLabel: "Close media",
                shareAccessibilityLabel: "Share media"
            ) {
                dismiss()
            }
        }
    }
}

private struct ChatInfoMediaBrowserPage: View {
    let item: ChatMediaItem
    @StateObject private var playbackController = VideoPlaybackController()
    @State private var image: CGImage?
    @State private var didFailImage = false
    @State private var documentPreviewItem: DocumentPreviewItem?

    var body: some View {
        Group {
            switch item.media.kind {
            case .photo, .sticker:
                photoPage
            case .video, .videoMessage:
                videoPage
            case .document:
                documentPage
            default:
                AttachmentPlaceholderView(title: item.media.kind.placeholderText, systemImage: "paperclip")
                    .foregroundStyle(.white)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var photoPage: some View {
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
        } else if didFailImage {
            AttachmentPlaceholderView(title: "Photo unavailable", systemImage: "photo")
                .foregroundStyle(.white)
                .padding()
        } else {
            ProgressView()
                .tint(.white)
                .task(id: item.media.fileURL) {
                    await loadImageIfNeeded()
                }
        }
    }

    @ViewBuilder
    private var videoPage: some View {
        if let url = item.media.fileURL {
            VideoPlayer(player: playbackController.player)
                .ignoresSafeArea()
                .overlay {
                    VideoPlaybackStatusOverlay(state: playbackController.loadingState)
                }
                .onAppear {
                    playbackController.load(url: url, restart: false)
                    playbackController.play()
                }
                .onDisappear {
                    playbackController.pause()
                }
        } else {
            AttachmentPlaceholderView(title: "Video unavailable", systemImage: "video")
                .foregroundStyle(.white)
                .padding()
        }
    }

    private var documentPage: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc")
                .font(.system(size: 54, weight: .semibold))

            Text(item.media.documentDisplayTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            if let url = item.media.fileURL {
                Button {
                    documentPreviewItem = DocumentPreviewItem(url: url)
                } label: {
                    Label("Open", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.white)
        .padding(32)
        #if os(iOS)
        .sheet(item: $documentPreviewItem) { item in
            DocumentPreviewView(url: item.url)
                .ignoresSafeArea()
        }
        #endif
    }

    private func loadImageIfNeeded() async {
        guard image == nil, !didFailImage, let url = item.media.fileURL else {
            return
        }

        let loadedImage = await Task.detached(priority: .utility) {
            downsampleImage(at: url, maxPixelSize: 2400)
        }.value

        if let loadedImage {
            image = loadedImage
        } else {
            didFailImage = true
        }
    }
}

private extension MessageRow {
    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let labels = [
            mediaCaptionText,
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
    let showSenderAvatar: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var audioPlayback: AudioPlaybackController
    @EnvironmentObject private var store: ArchiveStore
    @State private var avatarImage: CGImage?
    @State private var loadedAvatarID: String?

    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 36)
            }

            HStack(alignment: .top, spacing: 7) {
                if shouldShowAvatar {
                    MessageSenderAvatarView(
                        image: avatarImage,
                        initials: message.senderInitials,
                        seed: message.senderAvatarGroupingKey
                    )
                }

                VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
                    VStack(alignment: contentAlignment, spacing: 5) {
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
                    .padding(.horizontal, bubbleContentPadding.horizontal)
                    .padding(.vertical, bubbleContentPadding.vertical)
                    .background(bubblePalette.background, in: bubbleShape)
                    .overlay {
                        bubbleShape
                            .stroke(bubblePalette.border, lineWidth: 0.7)
                    }
                    .textSelection(.enabled)

                    if let messageDate = message.messageDate {
                        Text(Self.dateFormatter.string(from: messageDate))
                            .font(.caption2)
                            .foregroundStyle(bubblePalette.metadataText)
                    }
                }
            }

            if !message.isFromMe {
                Spacer(minLength: 36)
            }
        }
        .padding(.vertical, 1)
        .task(id: avatarTaskID) {
            await loadAvatarIfNeeded()
        }
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
            if let friendlyName = message.senderDisplayName {
                return friendlyName
            }
            return "Unknown sender"
        }
        return nil
    }

    private var shouldShowAvatar: Bool {
        isGroupChat && !message.isFromMe && showSenderAvatar
    }

    private var avatarTaskID: String {
        let senderSeed = message.senderAvatarGroupingKey
        return "\(senderSeed)|\(showSenderAvatar)|\(store.profileAvatarLoadingEnabled)"
    }

    private func loadAvatarIfNeeded() async {
        if loadedAvatarID != avatarTaskID {
            avatarImage = nil
            loadedAvatarID = avatarTaskID
        }

        guard shouldShowAvatar else { return }
        guard avatarImage == nil else { return }
        guard store.profileAvatarLoadingEnabled else { return }
        guard !Task.isCancelled else { return }

        if let loadedImage = await store.profileAvatarImage(
            forSenderJID: message.senderProfilePhotoJID,
            senderIdentifier: message.senderProfilePhotoIdentifier,
            fallbackIdentifier: message.senderAvatarGroupingKey,
            priority: .visible
        ) {
            guard !Task.isCancelled else { return }
            avatarImage = loadedImage
        }
    }

    private var senderNameColor: Color {
        if message.isFromMe {
            return bubblePalette.sentSenderNameText
        }

        let seed = message.groupMemberJID
            ?? message.senderJID
            ?? message.friendlySenderName
            ?? message.safeSenderPhoneNumber
            ?? senderLabel
            ?? "unknown"
        return bubblePalette.groupSenderNameText(seed: seed)
    }

    private var bubblePalette: ChatBubblePalette {
        ChatBubblePalette(isFromMe: message.isFromMe, colorScheme: colorScheme)
    }

    private var contentAlignment: HorizontalAlignment {
        if isGroupChat, senderLabel != nil {
            return .leading
        }
        return message.isFromMe ? .trailing : .leading
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

    private var bubbleContentPadding: (horizontal: CGFloat, vertical: CGFloat) {
        guard isCompactMediaBubble else {
            return (12, 8)
        }

        return (6, 6)
    }

    private var isPhotoOnlyBubble: Bool {
        guard senderLabel == nil,
              message.displayText == nil,
              message.media?.kind == .photo
        else {
            return false
        }
        return true
    }

    private var isCompactMediaBubble: Bool {
        guard message.media != nil else { return false }
        if isPhotoOnlyBubble { return true }
        return hasCaptionedAttachmentContent
    }

    private var hasCaptionedAttachmentContent: Bool {
        guard let media = message.media,
              messageSupportsCaptionedAttachment(media) else { return false }
        let candidate = message.mediaCaptionText ?? message.displayText ?? media.fallbackCaptionText
        return !(candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func messageSupportsCaptionedAttachment(_ media: MediaMetadata) -> Bool {
        switch media.kind {
        case .photo, .video, .videoMessage, .audio, .voiceMessage, .document, .media:
            return true
        case .contact, .location, .sticker, .linkPreview, .call, .callOrSystem, .system, .deleted:
            return false
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct MessageSenderAvatarView: View {
    let image: CGImage?
    let initials: String?
    let seed: String

    private var fallbackInitials: String {
        let cleanedInitials = initials?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleanedInitials.isEmpty ? "?" : cleanedInitials
    }

    private var seedIndex: Int {
        let clamped = Int(seed.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        return abs(clamped % senderAvatarPalette.count)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(senderAvatarPalette[seedIndex].gradient)

            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else if initials != nil {
                Text(fallbackInitials)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    private static let senderAvatarPalette: [Color] = [
        Color(red: 0.19, green: 0.51, blue: 0.75),
        Color(red: 0.35, green: 0.62, blue: 0.40),
        Color(red: 0.64, green: 0.38, blue: 0.17),
        Color(red: 0.69, green: 0.26, blue: 0.35),
        Color(red: 0.36, green: 0.35, blue: 0.70),
        Color(red: 0.22, green: 0.54, blue: 0.58)
    ]

    private var senderAvatarPalette: [Color] {
        Self.senderAvatarPalette
    }
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
            : Color(red: 0.205, green: 0.205, blue: 0.205)
    }

    var border: Color {
        guard colorScheme == .dark else {
            return Color.black.opacity(isFromMe ? 0.04 : 0.06)
        }

        return isFromMe
            ? Color.white.opacity(0.05)
            : Color.white.opacity(0.14)
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
        let normalizedSeed = seed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let palette: [Color]
        if colorScheme == .dark {
            palette = [
                Color(red: 0.49, green: 0.79, blue: 1.00),
                Color(red: 1.00, green: 0.74, blue: 0.42),
                Color(red: 0.96, green: 0.62, blue: 0.84),
                Color(red: 0.59, green: 0.88, blue: 0.70),
                Color(red: 0.82, green: 0.73, blue: 1.00),
                Color(red: 0.99, green: 0.63, blue: 0.58),
                Color(red: 0.50, green: 0.90, blue: 0.86),
                Color(red: 0.88, green: 0.82, blue: 0.46),
                Color(red: 0.71, green: 0.84, blue: 1.00),
                Color(red: 1.00, green: 0.68, blue: 0.78),
                Color(red: 0.66, green: 0.93, blue: 0.55),
                Color(red: 0.95, green: 0.72, blue: 1.00)
            ]
        } else {
            palette = [
                Color(red: 0.02, green: 0.37, blue: 0.73),
                Color(red: 0.64, green: 0.25, blue: 0.00),
                Color(red: 0.62, green: 0.18, blue: 0.47),
                Color(red: 0.08, green: 0.42, blue: 0.25),
                Color(red: 0.42, green: 0.28, blue: 0.75),
                Color(red: 0.74, green: 0.18, blue: 0.12),
                Color(red: 0.00, green: 0.46, blue: 0.50),
                Color(red: 0.52, green: 0.41, blue: 0.00),
                Color(red: 0.18, green: 0.34, blue: 0.70),
                Color(red: 0.66, green: 0.16, blue: 0.31),
                Color(red: 0.24, green: 0.45, blue: 0.10),
                Color(red: 0.55, green: 0.22, blue: 0.62)
            ]
        }

        let hash = normalizedSeed.unicodeScalars.reduce(UInt64(5381)) { partialHash, scalar in
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
                    .frame(maxWidth: mediaContentMaxWidth(for: media), alignment: mediaContentAlignment)
            } else if let displayText, let url = MessageLinkDetector.firstWebURL(in: displayText) {
                LinkPreviewAttachmentView(media: nil, fallbackURL: url, isFromMe: message.isFromMe)
            }

            if let media = message.media, isCaptionedAttachment(media), let renderedDisplayText {
                LinkedMessageText(text: renderedDisplayText)
                    .frame(maxWidth: mediaContentMaxWidth(for: media), alignment: mediaContentAlignment)
                    .textSelection(.enabled)
            } else if let renderedDisplayText {
                LinkedMessageText(text: renderedDisplayText)
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
        message.mediaCaptionText ?? message.displayText ?? message.media?.fallbackCaptionText
    }

    private var renderedDisplayText: String? {
        guard let displayText else { return nil }
        if shouldSuppressStandaloneLinkText(displayText) {
            return nil
        }
        return displayText
    }

    private func shouldSuppressStandaloneLinkText(_ text: String) -> Bool {
        let previewURL: URL?
        if let media = message.media, media.kind == .linkPreview {
            previewURL = media.linkPreviewURL ?? MessageLinkDetector.firstWebURL(in: media.title)
        } else if message.media == nil {
            previewURL = MessageLinkDetector.firstWebURL(in: text)
        } else {
            previewURL = nil
        }

        return MessageLinkDetector.isStandaloneWebURL(text, matching: previewURL)
    }

    private func shouldShowAttachment(for media: MediaMetadata) -> Bool {
        switch media.kind {
        case .photo, .video, .videoMessage, .audio, .voiceMessage, .document, .linkPreview:
            return true
        case .media:
            return true
        case .contact, .location, .sticker, .call, .callOrSystem, .system, .deleted:
            return displayText == nil
        }
    }

    private func isCaptionedAttachment(_ media: MediaMetadata) -> Bool {
        switch media.kind {
        case .photo, .video, .videoMessage, .audio, .voiceMessage, .document, .media:
            return true
        case .contact, .location, .sticker, .linkPreview, .call, .callOrSystem, .system, .deleted:
            return false
        }
    }

    private var mediaContentAlignment: Alignment {
        message.isFromMe ? .trailing : .leading
    }

    private func mediaContentMaxWidth(for media: MediaMetadata) -> CGFloat {
        switch media.kind {
        case .photo:
            return 268
        case .videoMessage:
            return 248
        case .video:
            return 260
        case .audio, .voiceMessage:
            return 300
        case .document:
            return 280
        default:
            return 268
        }
    }

    @ViewBuilder
    private func attachmentView(for media: MediaMetadata) -> some View {
        switch media.kind {
        case .photo:
            PhotoAttachmentView(media: media)
        case .video, .videoMessage:
            VideoAttachmentView(messageID: message.id, media: media, isFromMe: message.isFromMe)
        case .audio, .voiceMessage:
            AudioAttachmentView(messageID: message.id, media: media)
        case .contact:
            ContactAttachmentView(media: media)
        case .document:
            DocumentAttachmentView(media: media)
        case .linkPreview:
            LinkPreviewAttachmentView(media: media, fallbackURL: displayText.flatMap(MessageLinkDetector.firstWebURL(in:)), isFromMe: message.isFromMe)
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
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .textSelection(.enabled)
        }
        .fixedSize(horizontal: true, vertical: false)
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
    let isFromMe: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var thumbnail: CGImage?
    @State private var loadedThumbnailURL: URL?
    @State private var didFailThumbnail = false

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

    private var thumbnailURL: URL? {
        guard let media,
              media.isFileAvailableInArchive,
              media.isFileReadableInArchive,
              let fileURL = media.fileURL,
              isImagePreview(media, fileURL: fileURL)
        else {
            return nil
        }
        return fileURL
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
        VStack(alignment: .leading, spacing: 8) {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(alignment: .top, spacing: 10) {
                if thumbnail == nil {
                    linkIcon
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        if thumbnail != nil {
                            Image(systemName: "link")
                                .font(.system(size: 10, weight: .semibold))
                                .accessibilityHidden(true)
                        }

                        Text(subtitle)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(width: 268, alignment: .leading)
        .background(ChatBubblePalette.attachmentBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: thumbnailURL) {
            await loadThumbnailIfNeeded()
        }
    }

    private var linkIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ChatBubblePalette.subtleIconBackground(isFromMe: isFromMe, colorScheme: colorScheme))

            Image(systemName: "link")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ChatBubblePalette.subtleIconForeground(isFromMe: isFromMe, colorScheme: colorScheme))
        }
        .frame(width: 32, height: 32)
    }

    private func loadThumbnailIfNeeded() async {
        guard let thumbnailURL else {
            thumbnail = nil
            loadedThumbnailURL = nil
            didFailThumbnail = false
            return
        }

        if loadedThumbnailURL != thumbnailURL {
            thumbnail = nil
            loadedThumbnailURL = thumbnailURL
            didFailThumbnail = false
        }

        guard thumbnail == nil, !didFailThumbnail else {
            return
        }

        let loadedThumbnail = await Task.detached(priority: .utility) {
            downsampleImage(at: thumbnailURL, maxPixelSize: 420)
        }.value

        if let loadedThumbnail {
            thumbnail = loadedThumbnail
        } else {
            didFailThumbnail = true
        }
    }

    private func isImagePreview(_ media: MediaMetadata, fileURL: URL) -> Bool {
        if media.mimeType?.lowercased().hasPrefix("image/") == true {
            return true
        }

        let fileExtension = (media.fileExtensionLabel ?? fileURL.pathExtension).lowercased()
        return ["jpg", "jpeg", "png", "heic", "webp", "gif"].contains(fileExtension)
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

    static func isStandaloneWebURL(_ text: String, matching url: URL?) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              let url,
              let match = webLinks(in: trimmedText).first,
              match.range.location == 0,
              match.range.length == (trimmedText as NSString).length else {
            return false
        }

        return normalizedURLString(match.url) == normalizedURLString(url)
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

    private static func normalizedURLString(_ url: URL) -> String {
        var absoluteString = url.absoluteString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while absoluteString.last == "/" {
            absoluteString.removeLast()
        }
        return absoluteString
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
                        .scaledToFill()
                        .frame(width: previewSize.width, height: previewSize.height)
                        .clipped()
                        .clipShape(previewShape)
                        .overlay {
                            previewShape
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        }
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

    private var previewSize: CGSize {
        guard let image else {
            return CGSize(width: 260, height: 180)
        }

        let aspectRatio = CGFloat(image.width) / max(CGFloat(image.height), 1)
        let maxWidth: CGFloat = 268
        let maxHeight: CGFloat = 330
        let minHeight: CGFloat = 118

        if aspectRatio >= 1 {
            let height = min(max(maxWidth / aspectRatio, minHeight), 220)
            return CGSize(width: maxWidth, height: height)
        }

        let width = min(max(maxHeight * aspectRatio, 178), maxWidth)
        return CGSize(width: width, height: maxHeight)
    }

    private var previewShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
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

@MainActor
private final class InstantVideoPlaybackCoordinator: ObservableObject {
    @Published private(set) var activeMessageID: Int64?

    func setActiveMessageID(_ messageID: Int64?) {
        activeMessageID = messageID
    }
}

private struct VideoAttachmentView: View {
    let messageID: Int64
    let media: MediaMetadata
    let isFromMe: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var inlineVideoPlaybackCoordinator: InstantVideoPlaybackCoordinator
    @StateObject private var playbackController = VideoPlaybackController()
    @State private var thumbnail: CGImage?
    @State private var didFailThumbnail = false
    @State private var isPlayerPresented = false
    @ScaledMetric(relativeTo: .subheadline) private var statusOverlayInset: CGFloat = 10

    var body: some View {
        Group {
            if !media.isFileAvailableInArchive || media.fileURL == nil {
                AttachmentPlaceholderView(title: unavailableTitle, systemImage: "video")
            } else if let url = media.fileURL {
                ZStack(alignment: .center) {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.black.opacity(0.72))
                    }

                    if !isVideoMessage {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                    } else {
                        Circle()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: playButtonSize, height: playButtonSize)
                            .overlay {
                                Image(systemName: isInlinePlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: playIconSize, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .contentShape(Circle())
                            .highPriorityGesture(
                                TapGesture()
                                    .onEnded {
                                        handleInlinePlaybackTap(url: url)
                                    }
                            )
                            .accessibilityLabel(isInlinePlaying ? "Pause video message" : "Play video message")
                            .accessibilityAddTraits(.isButton)
                    }

                    if thumbnail == nil && !didFailThumbnail {
                        ProgressView()
                            .tint(.white)
                            .offset(y: isVideoMessage ? statusOverlayInset : 46)
                    }

                    if isVideoMessage,
                       playbackController.loadingState == .loading || playbackController.loadingState == .failed {
                        VideoPlaybackStatusOverlay(state: playbackController.loadingState)
                    }

                    if let durationText {
                        Text(durationText)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(.white)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(8)
                    }
                }
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(previewShape)
                .contentShape(previewShape)
                .overlay {
                    if isVideoMessage {
                        previewShape
                            .stroke(previewBorderColor, lineWidth: 0.9)
                    }
                }
                .accessibilityLabel(accessibilityLabel)
                .onTapGesture {
                    playbackController.load(url: url, restart: true)
                    isPlayerPresented = true
                }
                .task(id: media.fileURL) {
                    await loadThumbnailIfNeeded()
                }
                .onDisappear {
                    if inlineVideoPlaybackCoordinator.activeMessageID == messageID {
                        inlineVideoPlaybackCoordinator.setActiveMessageID(nil)
                    }
                    playbackController.pause()
                }
                .onChange(of: inlineVideoPlaybackCoordinator.activeMessageID) { _, activeMessageID in
                    if !isVideoMessage {
                        return
                    }
                    guard activeMessageID != messageID else {
                        return
                    }
                    playbackController.pause()
                }
                .fullScreenCover(isPresented: $isPlayerPresented) {
                    if let url = media.fileURL {
                        VideoPlayerSheet(controller: playbackController, url: url)
                    }
                }
            } else {
                AttachmentPlaceholderView(title: unavailableTitle, systemImage: "video")
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

    private var isInlinePlaying: Bool {
        inlineVideoPlaybackCoordinator.activeMessageID == messageID && playbackController.isActivePlayback
    }

    private var playButtonSize: CGFloat {
        54
    }

    private var playIconSize: CGFloat {
        26
    }

    private var durationText: String? {
        guard isVideoMessage, let durationSeconds = media.durationSeconds else {
            return nil
        }
        let roundedSeconds = Int(durationSeconds.rounded())
        guard roundedSeconds > 0 else { return nil }
        return String(format: "%d:%02d", roundedSeconds / 60, roundedSeconds % 60)
    }

    private var previewBorderColor: Color {
        isVideoMessage
            ? ChatBubblePalette(isFromMe: isFromMe, colorScheme: colorScheme).border.opacity(0.7)
            : .clear
    }

    private var previewSize: CGSize {
        isVideoMessage
            ? CGSize(width: instantVideoDiameter, height: instantVideoDiameter)
            : CGSize(width: 260, height: 160)
    }

    private var instantVideoDiameter: CGFloat {
        #if os(iOS)
        let fallbackWidth = UIScreen.main.bounds.width * 0.56
        #else
        let fallbackWidth: CGFloat = 230
        #endif
        return min(max(fallbackWidth, 220), 248)
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

    private func handleInlinePlaybackTap(url: URL) {
        if inlineVideoPlaybackCoordinator.activeMessageID == messageID {
            inlineVideoPlaybackCoordinator.setActiveMessageID(nil)
            playbackController.pause()
            return
        }

        inlineVideoPlaybackCoordinator.setActiveMessageID(messageID)
        playbackController.load(url: url, restart: false)
        playbackController.play()
    }
}

private enum VideoPlaybackLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed
}

private struct VideoPlaybackStatusOverlay: View {
    let state: VideoPlaybackLoadState

    var body: some View {
        Group {
            switch state {
            case .idle, .ready:
                EmptyView()
            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)

                    Text("Loading video...")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading video")
                .statusOverlayStyle()
            case .failed:
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)

                    Text("Could not load video")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Could not load video")
                .statusOverlayStyle()
            }
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    func statusOverlayStyle() -> some View {
        self
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct VideoPlayerSheet: View {
    @ObservedObject var controller: VideoPlaybackController
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VideoPlayer(player: controller.player)
                .ignoresSafeArea()
                .overlay {
                    VideoPlaybackStatusOverlay(state: controller.loadingState)
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            MediaViewerTopOverlay(
                shareURL: url,
                closeAccessibilityLabel: "Close video",
                shareAccessibilityLabel: "Share video"
            ) {
                dismiss()
            }
        }
        .onAppear {
            controller.load(url: url, restart: false)
            controller.play()
        }
        .onDisappear {
            controller.pause()
        }
    }
}

@MainActor
private final class VideoPlaybackController: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var loadingState: VideoPlaybackLoadState = .idle
    @Published private(set) var isActivePlayback: Bool = false
    private var loadedURL: URL?
    private var currentItemIdentifier: ObjectIdentifier?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?

    deinit {
        statusObservation?.invalidate()
        timeControlStatusObservation?.invalidate()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    func load(url: URL, restart: Bool) {
        guard loadedURL != url || loadingState == .failed else {
            if restart {
                player.seek(to: .zero)
            }
            return
        }

        player.pause()
        isActivePlayback = false
        statusObservation?.invalidate()
        statusObservation = nil

        let item = AVPlayerItem(url: url)
        let itemIdentifier = ObjectIdentifier(item)
        loadedURL = url
        currentItemIdentifier = itemIdentifier
        loadingState = .loading
        observeStatus(for: item, itemIdentifier: itemIdentifier)
        observeTimeControlStatusIfNeeded()
        player.replaceCurrentItem(with: item)
    }

    func play() {
        guard loadedURL != nil, loadingState != .failed else { return }
        prepareMediaPlaybackSession()
        player.play()
    }

    func pause() {
        player.pause()
        isActivePlayback = false
    }

    private func observeStatus(for item: AVPlayerItem, itemIdentifier: ObjectIdentifier) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, change in
            let status = change.newValue ?? observedItem.status
            Task { @MainActor in
                self?.updateLoadingState(for: status, itemIdentifier: itemIdentifier)
            }
        }
    }

    private func observeTimeControlStatusIfNeeded() {
        guard timeControlStatusObservation == nil else { return }
        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, change in
            let status = change.newValue ?? observedPlayer.timeControlStatus
            Task { @MainActor in
                self?.handleTimeControlStatus(status)
            }
        }
    }

    private func updateLoadingState(for status: AVPlayerItem.Status, itemIdentifier: ObjectIdentifier) {
        guard currentItemIdentifier == itemIdentifier else { return }

        switch status {
        case .unknown:
            loadingState = .loading
        case .readyToPlay:
            loadingState = .ready
        case .failed:
            loadingState = .failed
        @unknown default:
            loadingState = .failed
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        guard loadedURL != nil else { return }

        isActivePlayback = status == .playing

        if loadingState == .loading, status == .playing {
            loadingState = .ready
        }
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

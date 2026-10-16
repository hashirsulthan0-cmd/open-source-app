import SwiftUI

/// Shelf tab: files, links and text dropped onto the notch.
/// Click a card to open it, drag it out to use it elsewhere, right-click for more.
struct ShelfView: View {
    @ObservedObject var shelf: FileTrayManager
    let isDropTargeted: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(shelf.items.isEmpty ? "Shelf" : "Shelf · \(shelf.items.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if !shelf.items.isEmpty {
                    Button("Clear") { shelf.removeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(height: 26)

            if shelf.items.isEmpty {
                NotchEmptyState(
                    symbol: isDropTargeted ? "arrow.down.circle.fill" : "tray",
                    title: isDropTargeted ? "Drop to add" : "Your shelf is empty",
                    message: "Drag files, links or text onto the notch to keep them here."
                )
                .overlay { dropOutline }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        if isDropTargeted {
                            NotchCard(isHighlighted: true) {
                                VStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 22, weight: .medium))
                                    Text("Drop to add")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                        ForEach(shelf.items) { item in
                            ShelfCard(item: item, shelf: shelf)
                        }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
    }

    @ViewBuilder
    private var dropOutline: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }
}

private struct ShelfCard: View {
    let item: ShelfItem
    @ObservedObject var shelf: FileTrayManager

    var body: some View {
        NotchCard {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .opacity(item.kind == .file && !item.fileExists ? 0.45 : 1)
        .onTapGesture { shelf.open(item) }
        .onDrag { shelf.itemProvider(for: item) }
        .contextMenu {
            Button(item.kind == .text ? "Copy" : "Open") { shelf.open(item) }
            if item.kind == .file {
                Button("Show in Finder") { shelf.revealInFinder(item) }
                    .disabled(!item.fileExists)
            }
            if item.kind != .text {
                Button(item.kind == .file ? "Copy File" : "Copy Link") { shelf.copy(item) }
            }
            if item.youTube != nil, shelf.canDownloadVideos {
                Button("Download with yt-dlp") { shelf.download(item) }
            }
            Divider()
            Button("Remove from Shelf", role: .destructive) { shelf.remove(item) }
        }
        .help(helpText)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .file:
            VStack(spacing: 6) {
                if let path = item.filePath {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                }
                Text(item.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if !item.fileExists {
                    Text("File moved or deleted")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)

        case .link:
            if let youTube = item.youTube {
                YouTubeCardContent(item: item, youTube: youTube, shelf: shelf)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(item.displayName)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(8)
            }

        case .text:
            Text(item.text ?? "")
                .font(.system(size: 11))
                .lineLimit(7)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var helpText: String {
        if case .failed(let message) = shelf.downloads[item.id] {
            return "Download failed: \(message)"
        }
        return item.urlString ?? item.filePath ?? item.text ?? ""
    }
}

private struct YouTubeCardContent: View {
    let item: ShelfItem
    let youTube: YouTubeMetadata
    @ObservedObject var shelf: FileTrayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ThumbnailImage(url: youTube.thumbnailURL)
                .frame(height: 58)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 3)
                }

            Text(youTube.title ?? "YouTube video")
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(2)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button {
                    shelf.open(item)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                if shelf.canDownloadVideos {
                    downloadButton
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        switch shelf.downloads[item.id] {
        case .downloading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Saving")
            }
        case .finished:
            Button {
                NSWorkspace.shared.open(YTDLPDownloader.downloadsDirectory)
            } label: {
                Label("Saved", systemImage: "checkmark.circle.fill")
            }
            .foregroundStyle(.green)
        case .failed:
            Button {
                shelf.download(item)
            } label: {
                Label("Retry", systemImage: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.orange)
        case nil:
            Button {
                shelf.download(item)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }
}

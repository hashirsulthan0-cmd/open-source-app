import SwiftUI

/// Clipboard tab: a search bar above a scrolling row of recent copies.
/// Click a card to copy it again; right-click for more options.
struct ClipboardView: View {
    @ObservedObject var clipboard: ClipboardManager
    /// Changes when the search field should take keyboard focus (from the ⌃⌥V shortcut).
    var focusRequest = 0

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let items = clipboard.visibleItems

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("Search clipboard, including text in images", text: $clipboard.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)
                        .onSubmit {
                            // Return copies the first match, so search-then-paste is keyboard only.
                            if let first = clipboard.visibleItems.first {
                                clipboard.copyToPasteboard(first)
                            }
                        }
                    if !clipboard.searchText.isEmpty {
                        Button {
                            clipboard.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .glossySurface(cornerRadius: 13)

                Button {
                    clipboard.clearUnpinned()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .glossySurface(cornerRadius: 13)
                }
                .buttonStyle(.plain)
                .help("Clear history (pinned items are kept)")
                .disabled(clipboard.items.allSatisfy(\.isPinned))
            }

            if items.isEmpty {
                if clipboard.searchText.isEmpty {
                    NotchEmptyState(
                        symbol: "doc.on.clipboard",
                        title: "Nothing copied yet",
                        message: "Text, links, images and files you copy will show up here."
                    )
                } else {
                    NotchEmptyState(
                        symbol: "magnifyingglass",
                        title: "No matches",
                        message: "Nothing in your history matches “\(clipboard.searchText)”."
                    )
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(items) { item in
                            ClipboardCard(item: item, clipboard: clipboard)
                        }
                    }
                }
            }
        }
        .onAppear { focusIfRequested() }
        .onChange(of: focusRequest) { focusIfRequested() }
    }

    private func focusIfRequested() {
        guard focusRequest > 0 else { return }
        // Wait a moment for the window to become key before moving focus into it.
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            isSearchFocused = true
        }
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    @ObservedObject var clipboard: ClipboardManager

    @State private var showCopied = false

    var body: some View {
        NotchCard {
            VStack(alignment: .leading, spacing: 0) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()

                HStack(spacing: 4) {
                    Image(systemName: kindSymbol)
                    Text(item.sourceAppName ?? kindLabel)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.yellow.opacity(0.9))
                    }
                    Text(item.copiedAt.shortAge)
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .overlay {
                if showCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .onTapGesture {
            clipboard.copyToPasteboard(item)
            withAnimation(.easeOut(duration: 0.15)) { showCopied = true }
            Task {
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.easeIn(duration: 0.2)) { showCopied = false }
            }
        }
        .onDrag { dragProvider }
        .contextMenu {
            Button("Copy") { clipboard.copyToPasteboard(item) }
            Button(item.isPinned ? "Unpin" : "Pin") { clipboard.togglePin(item) }
            if item.kind == .link, let text = item.text, let url = URL(string: text) {
                Button("Open Link") { NSWorkspace.shared.open(url) }
            }
            if item.kind == .files {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs) }
            }
            if item.kind == .image, item.recognizedText != nil {
                Button("Copy Text from Image") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.recognizedText ?? "", forType: .string)
                }
            }
            Divider()
            Button("Delete", role: .destructive) { clipboard.delete(item) }
        }
        .help(item.text ?? item.recognizedText ?? "")
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            Text(item.text ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(6)
                .padding(8)

        case .link:
            if let youTube = item.youTube {
                VStack(alignment: .leading, spacing: 4) {
                    ThumbnailImage(url: youTube.thumbnailURL)
                        .frame(height: 58)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    Text(youTube.title ?? item.text ?? "")
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(URL(string: item.text ?? "")?.host ?? "")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(item.text ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue.opacity(0.9))
                        .lineLimit(4)
                }
                .padding(8)
            }

        case .image:
            ThumbnailImage(url: item.imageURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

        case .files:
            VStack(spacing: 6) {
                if let first = item.filePaths.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                    Text((first as NSString).lastPathComponent)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                if item.filePaths.count > 1 {
                    Text("+\(item.filePaths.count - 1) more")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
        }
    }

    private var kindSymbol: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .link: item.youTube != nil ? "play.rectangle.fill" : "link"
        case .image: "photo"
        case .files: "doc"
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .files: "Files"
        }
    }

    private var dragProvider: NSItemProvider {
        switch item.kind {
        case .text, .link:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .image:
            if let url = item.imageURL, let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
            return NSItemProvider()
        case .files:
            if let url = item.fileURLs.first, let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
            return NSItemProvider()
        }
    }
}

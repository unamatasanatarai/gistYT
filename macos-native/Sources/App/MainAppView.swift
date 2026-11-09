import SwiftUI
import AppKit

public enum DetailViewMode: String, CaseIterable, Identifiable {
    case preview = "Reading Preview"
    case rawMarkdown = "Raw Markdown"
    case transcript = "Transcript"

    public var id: String { rawValue }
}

public struct MainAppView: View {
    @ObservedObject var settings = SettingsStore.shared

    @State private var inputURL: String = ""
    @State private var isProcessing: Bool = false
    @State private var statusMessage: String = ""
    @State private var errorMessage: String? = nil

    @State private var currentMarkdown: String = ""
    @State private var currentTranscript: String = ""
    @State private var currentTitle: String = ""
    @State private var currentSummaryURL: URL? = nil
    @State private var currentTranscriptURL: URL? = nil

    @State private var viewMode: DetailViewMode = .preview
    @State private var savedItems: [SavedSummaryItem] = []
    @State private var selectedSlug: String? = nil
    @State private var searchQuery: String = ""
    @State private var showSettings: Bool = false
    @State private var showClearAllAlert: Bool = false
    @State private var copiedNotice: String? = nil
    @State private var hoveredSlug: String? = nil

    public init() {}

    private var hasValidInput: Bool {
        let trimmed = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && VideoIDParser.parseVideoID(from: trimmed) != nil
    }

    private var clipboardYouTubeURL: String? {
        guard let string = NSPasteboard.general.string(forType: .string) else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return VideoIDParser.parseVideoID(from: trimmed) != nil ? trimmed : nil
    }

    public var body: some View {
        HSplitView {
            // Left Sidebar: Minimalist Library
            sidebarView
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 360)

            // Right Main Content Area
            VStack(spacing: 0) {
                // Top Unified Search & Action Bar
                topActionBar

                // Subtle Thin Progress Line
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 2)
                } else {
                    Divider()
                }

                // Error / Notice Toast
                if let error = errorMessage {
                    errorBanner(text: error)
                }

                // Main Viewer
                if let selected = savedItems.first(where: { $0.slug == selectedSlug }), selected.isLoading {
                    inProgressCalloutView(item: selected)
                } else if !currentMarkdown.isEmpty {
                    detailContentView
                } else {
                    emptyStateView
                }
            }
            .frame(minWidth: 520)
        }
        .frame(minWidth: 840, minHeight: 580)
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .alert(isPresented: $showClearAllAlert) {
            Alert(
                title: Text("Clear All History?"),
                message: Text("All saved summaries and transcriptions will be moved to the macOS Trash."),
                primaryButton: .destructive(Text("Move to Trash")) {
                    clearAllHistory()
                },
                secondaryButton: .cancel()
            )
        }
        .onDeleteCommand {
            if let selected = savedItems.first(where: { $0.slug == selectedSlug && !$0.isLoading }) {
                deleteItem(selected)
            }
        }
        .background(
            Button(action: refreshSavedItems) { EmptyView() }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
        )
        .onAppear {
            refreshSavedItems()
            checkForClipboardURL()
        }
    }

    // MARK: - Top Unified Input Bar

    private var topActionBar: some View {
        HStack(spacing: 12) {
            // Unified Spotlight-style Address Capsule
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(hasValidInput ? Color(red: 0.12, green: 0.44, blue: 0.94) : .secondary)

                TextField("Paste YouTube link or enter video ID...", text: $inputURL)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, weight: .regular))
                    .onSubmit {
                        startSummarizing()
                    }

                // Quick Paste Badge (if empty & clipboard has a link)
                if inputURL.isEmpty, let clipURL = clipboardYouTubeURL {
                    Button(action: { inputURL = clipURL }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 10))
                            Text("Paste")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Paste YouTube URL from clipboard")
                }

                // Clear button
                if !inputURL.isEmpty {
                    Button(action: { inputURL = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                // Action Pill: Get Gist
                Button(action: startSummarizing) {
                    HStack(spacing: 5) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                            Text("Working...")
                                .font(.system(size: 12, weight: .semibold))
                        } else {
                            Text("Get Gist")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundColor(hasValidInput ? .white : Color.primary.opacity(0.35))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hasValidInput ? Color(red: 0.12, green: 0.44, blue: 0.94) : Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasValidInput || isProcessing)
                .keyboardShortcut(.defaultAction)
            }
            .padding(7)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(9)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Settings Button
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Settings & API Key")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Error Toast

    private func errorBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.red)
            Spacer()
            Button(action: { errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }

    // MARK: - Detail Content View

    private var detailContentView: some View {
        VStack(spacing: 0) {
            // Secondary Clean Toolbar
            HStack(spacing: 12) {
                // Clean Mode Tabs
                HStack(spacing: 2) {
                    ForEach(DetailViewMode.allCases) { mode in
                        let active = (viewMode == mode)
                        Button(action: { viewMode = mode }) {
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: active ? .semibold : .regular))
                                .foregroundColor(active ? .primary : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(active ? Color.primary.opacity(0.07) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)

                Spacer()

                // Actions Group
                HStack(spacing: 6) {
                    if let fileURL = currentSummaryURL {
                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(width: 26, height: 26)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }

                    if let currentItem = savedItems.first(where: { $0.slug == selectedSlug && !$0.isLoading }) {
                        Button(action: { deleteItem(currentItem) }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(width: 26, height: 26)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Move brief to Trash (⌫)")
                    }
                }

                // Copy Notice Toast
                if let notice = copiedNotice {
                    Text(notice)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // View Content
            switch viewMode {
            case .preview:
                MarkdownPreviewView(markdown: currentMarkdown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .rawMarkdown:
                ScrollView {
                    Text(currentMarkdown)
                        .font(.system(size: 13, design: .monospaced))
                        .lineSpacing(4)
                        .padding(32)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color(NSColor.textBackgroundColor))
            case .transcript:
                ScrollView {
                    Text(currentTranscript.isEmpty ? "No transcript loaded." : currentTranscript)
                        .font(.system(size: 14, design: .serif))
                        .lineSpacing(6)
                        .padding(36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }

    // MARK: - In-Progress Callout View

    private func inProgressCalloutView(item: SavedSummaryItem) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 24)

                // Over-exaggerated redneck drawing sketch with drink & pointing finger
                if let imgURL = Bundle.main.url(forResource: "hold_on", withExtension: "png"),
                   let nsImg = NSImage(contentsOf: imgURL) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 320, maxHeight: 320)
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
                }

                // Status indicator directly beneath image (no card box, text is on image)
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 14, height: 14)
                        Text(statusMessage.isEmpty ? "Distilling captions & brewing your brief..." : statusMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Text(item.title)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.top, 4)

                Spacer(minLength: 24)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
               let nsImg = NSImage(contentsOf: iconURL) {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(18)
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
            } else {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 46))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Text("No Video Selected")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Text("Paste any YouTube link in the address bar above and press ↵ Return to generate a clean, executive brief.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: { showSettings = true }) {
                    Label("Configure Gemini API Key", systemImage: "key.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left Sidebar: Minimalist Library

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Search Input
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("Search history...", text: $searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12))
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(10)

            Divider()

            // Filtered Items
            let filtered = savedItems.filter { item in
                if searchQuery.isEmpty { return true }
                return item.title.localizedCaseInsensitiveContains(searchQuery) ||
                       (item.channel?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No summaries")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { item in
                            sidebarItemRow(item: item)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Sidebar Item Row

    private func sidebarItemRow(item: SavedSummaryItem) -> some View {
        let isSelected = (selectedSlug == item.slug)
        let isHovered = (hoveredSlug == item.slug)

        return HStack(alignment: .top, spacing: 9) {
            // Indicator: Spinner when loading, or subtle icon
            if item.isLoading {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 14)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(2)
                    .foregroundColor(item.isLoading ? .secondary : .primary)

                HStack(alignment: .center) {
                    if let ch = item.channel {
                        Text(ch)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()

                    if isHovered && !item.isLoading {
                        Button(action: { deleteItem(item) }) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.8))
                                .padding(2)
                        }
                        .buttonStyle(.plain)
                        .help("Move to Trash")
                    } else {
                        Text(item.isLoading ? "Working..." : formatDate(item.date))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .leading) {
                // Refined, subtle selection highlight (No loud green flood!)
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(NSColor.selectedContentBackgroundColor).opacity(0.12))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(red: 0.12, green: 0.44, blue: 0.94))
                        .frame(width: 3)
                        .padding(.vertical, 4)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.04))
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSlug = item.slug
            if !item.isLoading {
                loadSavedItem(item)
            }
        }
        .onHover { h in
            hoveredSlug = h ? item.slug : nil
        }
        .contextMenu {
            if !item.isLoading {
                Button(role: .destructive, action: { deleteItem(item) }) {
                    Label("Move to Trash", systemImage: "trash")
                }
                if let sumURL = item.summaryPath {
                    Button(action: { NSWorkspace.shared.activateFileViewerSelecting([sumURL]) }) {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                }
            }
        }
    }

    // MARK: - Logic & Summarizing Pipeline

    private func startSummarizing() {
        guard !isProcessing else { return }

        let raw = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let videoID = VideoIDParser.parseVideoID(from: raw) else {
            errorMessage = "Please enter a valid YouTube video URL or ID."
            return
        }

        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.isEmpty {
            errorMessage = "GEMINI_API_KEY is not set. Please set your key in Settings."
            showSettings = true
            return
        }

        isProcessing = true
        errorMessage = nil
        statusMessage = "Connecting..."

        let placeholderSlug = "loading_\(videoID)_\(UUID().uuidString.prefix(4))"
        let placeholderItem = SavedSummaryItem(
            slug: placeholderSlug,
            title: "Summarizing \(videoID)...",
            channel: "Fetching captions...",
            date: Date(),
            summaryPath: nil,
            transcriptPath: nil,
            isLoading: true
        )

        savedItems.insert(placeholderItem, at: 0)
        selectedSlug = placeholderSlug
        inputURL = ""

        Task {
            do {
                await MainActor.run {
                    statusMessage = "Fetching captions..."
                }
                let transcriptResult = try await YouTubeService.shared.fetchTranscript(
                    videoID: videoID,
                    preferredLangs: settings.parsedLanguages,
                    browserCookies: settings.browserCookies
                )

                let watchUrl = VideoIDParser.watchURL(for: videoID).absoluteString
                var headerLines = ["Title: \(transcriptResult.title ?? "(unknown)")"]
                if let ch = transcriptResult.channel { headerLines.append("Channel: \(ch)") }
                headerLines.append("URL: \(watchUrl)")
                if let dur = DurationFormatter.format(seconds: transcriptResult.duration) {
                    headerLines.append("Duration: \(dur)")
                }
                headerLines.append("Captions: \(transcriptResult.captions)")
                let fullTranscriptText = headerLines.joined(separator: "\n") + "\n\n" + transcriptResult.text

                let (summary, model) = try await GeminiService.shared.summarize(
                    transcriptText: fullTranscriptText,
                    apiKey: apiKey,
                    onStatusChange: { msg in
                        Task { @MainActor in
                            self.statusMessage = msg
                        }
                    }
                )

                let slug = SlugGenerator.makeSlug(title: transcriptResult.title, videoID: videoID)
                let markdown = MarkdownRenderer.renderMarkdown(
                    summary: summary,
                    title: transcriptResult.title ?? slug,
                    channel: transcriptResult.channel,
                    duration: DurationFormatter.format(seconds: transcriptResult.duration),
                    url: watchUrl,
                    model: model,
                    sourceFilename: "transcriptions/\(slug).txt",
                    date: Date()
                )

                let (transDir, sumDir) = try await StorageService.shared.ensureDirectories(base: settings.effectiveSaveDirectory)
                let tURL = try await StorageService.shared.saveTranscript(
                    result: transcriptResult,
                    slug: slug,
                    directory: transDir
                )
                let sURL = try await StorageService.shared.saveSummary(
                    markdown: markdown,
                    slug: slug,
                    directory: sumDir
                )

                await MainActor.run {
                    self.currentMarkdown = markdown
                    self.currentTranscript = fullTranscriptText
                    self.currentTitle = transcriptResult.title ?? slug
                    self.currentSummaryURL = sURL
                    self.currentTranscriptURL = tURL
                    self.viewMode = .preview
                    self.isProcessing = false
                    self.statusMessage = ""

                    let finalItem = SavedSummaryItem(
                        slug: slug,
                        title: transcriptResult.title ?? slug,
                        channel: transcriptResult.channel,
                        date: Date(),
                        summaryPath: sURL,
                        transcriptPath: tURL,
                        isLoading: false
                    )
                    self.savedItems.removeAll(where: { $0.slug == placeholderSlug || $0.slug == slug })
                    self.savedItems.insert(finalItem, at: 0)
                    self.selectedSlug = slug
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
                    self.savedItems.removeAll(where: { $0.slug == placeholderSlug })
                    if self.selectedSlug == placeholderSlug {
                        self.selectedSlug = self.savedItems.first?.slug
                    }
                }
            }
        }
    }

    private func pasteFromClipboard() {
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        inputURL = string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func checkForClipboardURL() {
        if inputURL.isEmpty, let string = NSPasteboard.general.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if VideoIDParser.parseVideoID(from: trimmed) != nil {
                inputURL = trimmed
            }
        }
    }

    private func copyTLDR() {
        let lines = currentMarkdown.components(separatedBy: .newlines)
        if let line = lines.first(where: { $0.hasPrefix("> **TL;DR**") }) {
            let tldr = line.replacingOccurrences(of: "> **TL;DR**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tldr, forType: .string)
            showNotice("TL;DR copied!")
        }
    }

    private func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentMarkdown, forType: .string)
        showNotice("Markdown copied!")
    }

    private func showNotice(_ text: String) {
        copiedNotice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if copiedNotice == text {
                copiedNotice = nil
            }
        }
    }

    private func loadSavedItem(_ item: SavedSummaryItem) {
        selectedSlug = item.slug
        if let path = item.summaryPath, let md = try? String(contentsOf: path, encoding: .utf8) {
            currentMarkdown = md
            currentTitle = item.title
            currentSummaryURL = path
            viewMode = .preview
        }
        if let tURL = item.transcriptPath, let txt = try? String(contentsOf: tURL, encoding: .utf8) {
            currentTranscript = txt
            currentTranscriptURL = tURL
        } else {
            currentTranscript = ""
            currentTranscriptURL = nil
        }
    }

    private func refreshSavedItems() {
        Task {
            let base = settings.effectiveSaveDirectory
            let (_, sumDir) = try await StorageService.shared.ensureDirectories(base: base)
            let items = await StorageService.shared.loadRecentSummaries(directory: sumDir)
            await MainActor.run {
                let loadingItems = self.savedItems.filter { $0.isLoading }
                self.savedItems = loadingItems + items.filter { item in
                    !loadingItems.contains(where: { $0.slug == item.slug })
                }
                if self.selectedSlug == nil {
                    self.selectedSlug = self.savedItems.first?.slug
                    if let first = self.savedItems.first, !first.isLoading {
                        loadSavedItem(first)
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Deletion & History Management

    private func deleteItem(_ item: SavedSummaryItem) {
        Task {
            do {
                try await StorageService.shared.deleteSummaryItem(item)
                await MainActor.run {
                    let wasSelected = (self.selectedSlug == item.slug)
                    self.savedItems.removeAll(where: { $0.slug == item.slug })
                    if wasSelected {
                        if let next = self.savedItems.first(where: { !$0.isLoading }) {
                            self.loadSavedItem(next)
                        } else {
                            self.currentMarkdown = ""
                            self.currentTranscript = ""
                            self.currentTitle = ""
                            self.currentSummaryURL = nil
                            self.currentTranscriptURL = nil
                            self.selectedSlug = nil
                        }
                    }
                    self.showNotice("Moved to Trash")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to delete: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearAllHistory() {
        Task {
            do {
                let base = settings.effectiveSaveDirectory
                try await StorageService.shared.clearAllHistory(base: base)
                await MainActor.run {
                    self.savedItems.removeAll(where: { !$0.isLoading })
                    if let loading = self.savedItems.first {
                        self.selectedSlug = loading.slug
                    } else {
                        self.currentMarkdown = ""
                        self.currentTranscript = ""
                        self.currentTitle = ""
                        self.currentSummaryURL = nil
                        self.currentTranscriptURL = nil
                        self.selectedSlug = nil
                    }
                    self.showNotice("All history moved to Trash")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to clear history: \(error.localizedDescription)"
                }
            }
        }
    }
}

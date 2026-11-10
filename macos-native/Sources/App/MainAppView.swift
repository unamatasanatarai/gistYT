import SwiftUI
import AppKit

public enum DetailViewMode: String, CaseIterable, Identifiable {
    case preview = "Reading Preview"
    case rawMarkdown = "Raw Markdown"
    case transcript = "Transcript"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .preview: return "Preview"
        case .rawMarkdown: return "Markdown"
        case .transcript: return "Transcript"
        }
    }
}

/// One in-flight video: its task (for cancellation) and the status shown on its row.
struct SummaryJob {
    let videoID: String
    var status: String
    var task: Task<Void, Never>? = nil
}

public struct MainAppView: View {
    @ObservedObject var settings = SettingsStore.shared

    @State private var inputURL: String = ""
    /// Running fetch+summarize jobs, keyed by their placeholder row's slug.
    @State private var jobs: [String: SummaryJob] = [:]
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
    @State private var showSidebar: Bool = true
    @FocusState private var isURLFieldFocused: Bool

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
        ZStack(alignment: .top) {
            HSplitView {
                if showSidebar {
                    // Left Sidebar: Minimalist Library
                    sidebarView
                        .frame(minWidth: 160, idealWidth: 220, maxWidth: 360)
                }

                // Right Main Content Area
                VStack(spacing: 0) {
                    // Top Unified Search & Action Bar
                    topActionBar

                    // Subtle Thin Progress Line
                    if !jobs.isEmpty {
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
                .frame(minWidth: 240)
            }

            // Gentle Popout Toast
            if let notice = copiedNotice {
                gentleNoticeToast(notice: notice)
                    .padding(.top, 54)
                    .zIndex(100)
            }
        }
        .frame(minWidth: 400, minHeight: 500)
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
            ZStack {
                Button(action: refreshSavedItems) { EmptyView() }
                    .keyboardShortcut("r", modifiers: .command)
                Button(action: cancelSelectedJob) { EmptyView() }
                    .keyboardShortcut(.cancelAction)
            }
            .opacity(0)
        )
        .onAppear {
            refreshSavedItems()
            checkForClipboardURL()
            focusURLField()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Returning to the app: put the cursor back in the URL field unless
            // the user is already typing somewhere else (e.g. history search).
            if !(NSApp.keyWindow?.firstResponder is NSTextView) {
                focusURLField()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .confirmQuitRequested)) { _ in
            showNotice("Press ⌘Q again to quit")
        }
    }

    // MARK: - Top Unified Input Bar

    private var topActionBar: some View {
        HStack(spacing: 8) {
            // Sidebar Toggle
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showSidebar.toggle() } }) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13))
                    .foregroundColor(showSidebar ? .secondary : Color(red: 0.12, green: 0.44, blue: 0.94))
                    .frame(width: 30, height: 30)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(showSidebar ? "Hide Sidebar (⌘⌥S)" : "Show Sidebar (⌘⌥S)")
            .keyboardShortcut("s", modifiers: [.command, .option])

            // Unified Spotlight-style Address Capsule
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(hasValidInput ? Color(red: 0.12, green: 0.44, blue: 0.94) : .secondary)

                TextField("Paste YouTube link or enter video ID...", text: $inputURL)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, weight: .regular))
                    .focused($isURLFieldFocused)
                    .onSubmit {
                        startSummarizing()
                        focusURLField()
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
                        Text("Get Gist")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
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
                .disabled(!hasValidInput)
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
                            Text(mode.shortTitle)
                                .font(.system(size: 11, weight: active ? .semibold : .regular))
                                .foregroundColor(active ? .primary : .secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
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
            }
            .padding(.horizontal, 14)
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
                        Text(jobs[item.slug]?.status ?? "Distilling captions & brewing your brief...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Text(item.title)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))

                    Button("Cancel") { cancelJob(item.slug) }
                        .help("Stop this video (Esc)")
                        .padding(.top, 6)
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
                    if let ch = item.isLoading ? jobs[item.slug]?.status : item.channel {
                        Text(ch)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()

                    if isHovered && item.isLoading {
                        Button(action: { cancelJob(item.slug) }) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.8))
                                .padding(2)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel")
                    } else if isHovered {
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
            if item.isLoading {
                Button(action: { cancelJob(item.slug) }) {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            } else {
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

    /// Starts a background job for the URL in the input field and immediately clears the
    /// field, so URLs can be queued back to back (paste, Return, paste, Return...).
    /// Each job owns a placeholder row in the sidebar until it finishes or fails.
    private func startSummarizing() {
        let raw = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Return can reach both onSubmit and the default button; the first call already
        // took the URL and cleared the field, so the second must be a silent no-op.
        guard !raw.isEmpty else { return }
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

        inputURL = ""
        errorMessage = nil
        focusURLField()

        // The same video submitted twice while its first job runs: show that job instead
        // of paying for a second fetch and summary.
        if let running = jobs.first(where: { $0.value.videoID == videoID }) {
            selectedSlug = running.key
            return
        }

        // If a video id is already in the list of gisted videos, instead of running the action again, just focus on the existing gist
        if let existing = savedItems.first(where: { item in
            if item.isLoading { return false }
            if item.videoID == videoID { return true }
            if item.slug == videoID || item.slug.hasSuffix("-\(videoID)") { return true }
            if let sumURL = item.summaryPath, StorageService.videoID(inFileAt: sumURL) == videoID { return true }
            return false
        }) {
            if !searchQuery.isEmpty {
                searchQuery = ""
            }
            loadSavedItem(existing)
            showNotice("Focused existing gist")
            return
        }

        let placeholderSlug = "loading_\(videoID)_\(UUID().uuidString.prefix(8))"
        let placeholderItem = SavedSummaryItem(
            slug: placeholderSlug,
            title: "Summarizing \(videoID)...",
            channel: nil,
            date: Date(),
            summaryPath: nil,
            transcriptPath: nil,
            isLoading: true,
            videoID: videoID
        )

        savedItems.insert(placeholderItem, at: 0)
        selectedSlug = placeholderSlug
        jobs[placeholderSlug] = SummaryJob(videoID: videoID, status: "Fetching captions...")

        let preferredLangs = settings.parsedLanguages
        let browserCookies = settings.browserCookies
        let saveDirectory = settings.effectiveSaveDirectory

        let task = Task {
            do {
                let transcriptResult = try await YouTubeService.shared.fetchTranscript(
                    videoID: videoID,
                    preferredLangs: preferredLangs,
                    browserCookies: browserCookies
                )
                await MainActor.run {
                    self.jobFetchedCaptions(placeholderSlug, title: transcriptResult.title)
                }

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
                            self.setJobStatus(placeholderSlug, msg)
                        }
                    }
                )

                let (transDir, sumDir) = try await StorageService.shared.ensureDirectories(base: saveDirectory)
                let slug = await StorageService.shared.uniqueSlug(
                    SlugGenerator.makeSlug(title: transcriptResult.title, videoID: videoID),
                    videoID: videoID,
                    transcriptions: transDir,
                    summaries: sumDir
                )
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

                try Task.checkCancellation()
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

                let finalItem = SavedSummaryItem(
                    slug: slug,
                    title: transcriptResult.title ?? slug,
                    channel: transcriptResult.channel,
                    date: Date(),
                    summaryPath: sURL,
                    transcriptPath: tURL,
                    isLoading: false,
                    videoID: videoID
                )
                await MainActor.run {
                    self.jobSucceeded(
                        placeholderSlug,
                        item: finalItem,
                        markdown: markdown,
                        transcript: fullTranscriptText
                    )
                }
            } catch {
                let cancelled = isCancellationError(error)
                await MainActor.run {
                    self.jobFailed(placeholderSlug, videoID: videoID, error: error, cancelled: cancelled)
                }
            }
        }
        jobs[placeholderSlug]?.task = task
    }

    private func setJobStatus(_ placeholderSlug: String, _ status: String) {
        jobs[placeholderSlug]?.status = status
    }

    private func jobFetchedCaptions(_ placeholderSlug: String, title: String?) {
        if let title = title, let index = savedItems.firstIndex(where: { $0.slug == placeholderSlug }) {
            savedItems[index].title = title
        }
        setJobStatus(placeholderSlug, "Summarizing...")
    }

    private func jobSucceeded(_ placeholderSlug: String, item: SavedSummaryItem, markdown: String, transcript: String) {
        jobs[placeholderSlug] = nil

        // Replace the placeholder in place so rows don't jump around while other jobs
        // are still running; drop an older row for the same file (a re-run).
        savedItems.removeAll(where: { $0.slug == item.slug && !$0.isLoading })
        if let index = savedItems.firstIndex(where: { $0.slug == placeholderSlug }) {
            savedItems[index] = item
        } else {
            savedItems.insert(item, at: 0)
        }

        // Only take over the detail pane if the user is still watching this job.
        if selectedSlug == placeholderSlug {
            selectedSlug = item.slug
            currentMarkdown = markdown
            currentTranscript = transcript
            currentTitle = item.title
            currentSummaryURL = item.summaryPath
            currentTranscriptURL = item.transcriptPath
            viewMode = .preview
        }
    }

    private func jobFailed(_ placeholderSlug: String, videoID: String, error: Error, cancelled: Bool) {
        jobs[placeholderSlug] = nil
        let title = savedItems.first(where: { $0.slug == placeholderSlug })?.title ?? videoID
        if cancelled {
            showNotice("Cancelled")
        } else {
            errorMessage = "\(title): \(error.localizedDescription)"
        }
        savedItems.removeAll(where: { $0.slug == placeholderSlug })
        if selectedSlug == placeholderSlug {
            selectFallbackItem()
        }
    }

    /// Cancels one job: terminates its yt-dlp run and aborts its in-flight HTTP requests.
    /// The job's catch block then removes its placeholder row.
    private func cancelJob(_ placeholderSlug: String) {
        jobs[placeholderSlug]?.task?.cancel()
    }

    /// Esc: cancel the job whose placeholder is selected.
    private func cancelSelectedJob() {
        if let slug = selectedSlug, jobs[slug] != nil {
            cancelJob(slug)
        }
    }

    /// After the selected row disappears, select the next row and show it.
    private func selectFallbackItem() {
        if let next = savedItems.first {
            selectedSlug = next.slug
            if !next.isLoading {
                loadSavedItem(next)
            }
        } else {
            selectedSlug = nil
        }
    }

    private func pasteFromClipboard() {
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        inputURL = string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Puts the text cursor in the URL field. Deferred one runloop tick (and backed up by 0.1s)
    /// because on macOS 12 setting focus before the window is key or during list layout is silently ignored.
    private func focusURLField() {
        DispatchQueue.main.async {
            self.isURLFieldFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isURLFieldFocused = true
        }
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
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            copiedNotice = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if self.copiedNotice == text {
                withAnimation(.easeInOut(duration: 0.22)) {
                    self.copiedNotice = nil
                }
            }
        }
    }

    private func gentleNoticeToast(notice: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: noticeIcon(for: notice))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(red: 0.12, green: 0.44, blue: 0.94))

            Text(notice)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 5)
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.85).combined(with: .opacity).combined(with: .offset(y: -8)),
                removal: .scale(scale: 0.92).combined(with: .opacity)
            )
        )
    }

    private func noticeIcon(for text: String) -> String {
        if text.contains("⌘Q") || text.contains("quit") {
            return "command"
        } else if text.contains("exist") || text.contains("Focus") {
            return "arrow.right.circle.fill"
        } else if text.contains("cop") || text.contains("Cop") {
            return "checkmark.circle.fill"
        } else if text.contains("Cancel") {
            return "xmark.circle.fill"
        } else {
            return "info.circle.fill"
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

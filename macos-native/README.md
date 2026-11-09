# gistYT

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="gistYT App Icon" />
</p>

<p align="center">
  <strong>Instant YouTube intelligence on your Mac: Turn any video into a clean, actionable brief in seconds.</strong>
  <br />
  A native macOS desktop application that extracts video transcripts and synthesizes structured summaries with Google Gemini.
</p>

<p align="center">
  <a href="https://github.com/unamatasanatarai/gistYT/releases"><img src="https://img.shields.io/github/v/release/unamatasanatarai/gistYT?label=release" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/macOS-12.0%2B-blue?logo=apple" alt="macOS 12.0+" />
  <img src="https://img.shields.io/badge/Swift-Native%20AppKit-F05138?logo=swift&logoColor=white" alt="Swift AppKit" />
  <img src="https://img.shields.io/badge/Gemini-3.8%20%7C%203.6%20%7C%203.5-4285F4?logo=googlegemini&logoColor=white" alt="Gemini Rotation" />
  <img src="https://img.shields.io/badge/tests-16%20passing-brightgreen" alt="16 Tests Passing" />
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License" />
</p>

---

## Why gistYT

Long-form YouTube videos often hide five minutes of critical insight inside an hour of video. Auto-generated captions are difficult to skim—lacking punctuation, cluttered with sound tags like `[Music]`, and frequently in other languages.

**gistYT** eliminates the video scrub. Paste any YouTube URL to extract its transcript, run it through Google Gemini's multimodal models, and produce a structured brief designed for rapid scanning. Every summary is delivered in clear English, formatted identically, and preserved as a local Markdown file on your Mac.

---

## Key Capabilities

### Instant Transcript Extraction
Pulls metadata and subtitle tracks across standard links, short URLs (`youtu.be`), Shorts, and bare video IDs. Uses an embedded, self-contained `yt-dlp` engine that automatically selects the highest-quality manual or auto-generated caption stream.

### Structured English Briefs
Generates five distinct, high-signal sections for every video:
* **TL;DR**: A one-sentence takeaway capturing the core message.
* **Summary**: 2–4 concise paragraphs explaining what the video covers.
* **Key Points**: 5–10 chronologically ordered, self-contained takeaways.
* **Notable Quotes**: Verbatim statements translated to English when applicable.
* **Topic Tags**: Concise categorization keywords for instant reference.

### Multi-Model Gemini Failover
Guarantees reliable generation through an automated model rotation hierarchy (`gemini-3.8-flash` → `gemini-3.6-flash` → `gemini-3.5-flash-lite` → `gemini-3.1-flash-lite`). If a model experiences rate limits or server pressure, gistYT seamlessly falls back to the next model in sequence without interrupting your flow.

### Built-In Local Library
Maintains a persistent, searchable archive in `~/Documents/gistYT/`. Filter your previous briefs instantly by title or channel, toggle between the structured brief and raw timestamped transcript, or reveal files directly in Finder.

### Native Typography & Reader Experience
Renders formatted Markdown directly using native AppKit typography—complete with styled callout cards for the TL;DR, clear list layouts, blockquotes, and one-click external links to the original video.

### Cookie-Authenticated Extraction
Access captions from age-gated, unlisted, or member-only videos by delegating authentication to your installed browser profile (Safari, Chrome, Firefox, Brave, Edge, or Chromium).

---

## How It Works

```text
1. Paste URL (⌘V) ──▶ 2. Extract Transcript ──▶ 3. Gemini Rotation ──▶ 4. Structured Brief
   (Any YouTube link)     (Embedded yt-dlp)       (Multi-model failover)   (Saved as .md)
```

1. **Input**: Paste any YouTube link or video ID with `⌘V` and click **Get Gist**.
2. **Extraction**: The bundled engine inspects video details, resolves title and duration, and fetches the cleanest subtitle track.
3. **Synthesis**: The transcript is transmitted to Google AI Studio with a strict schema constraint, rotating models if necessary.
4. **Output**: Read the rendered brief immediately in the app, inspect the raw transcript, or open the Markdown file in your notes app.

---

## What Makes It Different

* **Zero Electron Bloat**: Built purely in native Swift and AppKit. Launches instantly, consumes minimal memory, and adheres strictly to macOS design conventions.
* **No Python or Homebrew Runtime Needed**: Packages the extraction engine internally. You do not need to install Python, `yt-dlp`, or node dependencies on your system.
* **Local-First Ownership**: Summaries and transcripts are saved as plain `.md` and `.txt` files in your Documents folder. Your data is not locked in a proprietary database.
* **Resilient Model Rotation**: Handles API quota exhaustion and transient errors automatically through client-side rotation across four Gemini tiers.

---

## Supported Integrations

* **YouTube**: Extracts metadata, chapters, durations, and subtitles via bundled `yt-dlp`.
* **Google Gemini API**: Direct REST communication with Google AI Studio using Gemini Flash models.
* **macOS Finder**: Full integration with the macOS Trash lifecycle and Finder reveal actions.
* **Desktop Browsers**: Safe cookie extraction support for Chrome, Safari, Firefox, Brave, Edge, and Chromium.

---

## Quick Start

### Download the Application

1. Download the latest **`gistYT-<version>.dmg`** package from the [Releases](https://github.com/unamatasanatarai/gistYT/releases) page.
2. Open the disk image and drag **gistYT** into your `/Applications` directory.
3. Launch **gistYT**, open Settings (`⌘,`), and enter your [Gemini API Key](https://aistudio.google.com/apikey).

### Build from Source

Build directly with the included `Makefile` (no third-party package managers required):

```bash
# Clone the repository and navigate to the macOS native directory
cd macos-native

# Compile the application bundle into build/gistYT.app
make build

# Launch the app
make run

# Build a styled release DMG
make dmg
```

---

## Configuration

Access the Settings Sheet via the gear icon or `⌘,`:

| Setting | Default | Description |
|---|---|---|
| **Gemini API Key** | Empty | Google AI Studio API key (`GEMINI_API_KEY`) used for summary generation. |
| **Caption Languages** | `en,pl,es,de,fr` | Comma-separated language codes searched in priority order. |
| **Browser Cookies** | `None` | Select browser profile (`chrome`, `safari`, `firefox`, etc.) for authenticated captions. |
| **Save Directory** | `~/Documents/gistYT` | Root location for storing `summaries/` and `transcriptions/`. |

---

## Keyboard Shortcuts

* **`⌘V`**: Paste YouTube link into the input bar.
* **`Return`**: Fetch transcript and generate brief.
* **`⌘R`**: Refresh saved library briefs.
* **`⌘,`**: Open Application Settings.
* **`⌘W`**: Close application window.

---

## Testing & Quality

gistYT includes a dedicated native Swift test suite verifying URL parsing, slug generation, cue formatting, duration calculation, and markdown generation:

```bash
make test
```

```text
==================================================
         Running Swift Native Test Suite          
==================================================
  ✔ PASS: AppConfig returns valid non-empty application name
  ✔ PASS: AppConfig returns valid bundle identifier
  ✔ PASS: VideoIDParser parses bare 11-char ID
  ✔ PASS: VideoIDParser parses watch URL with tracking params
  ✔ PASS: VideoIDParser parses youtu.be short URL
  ✔ PASS: VideoIDParser parses shorts and embed URLs
  ✔ PASS: VideoIDParser rejects invalid inputs
  ✔ PASS: SlugGenerator produces lowercase ASCII slug
  ✔ PASS: SlugGenerator falls back to videoID on empty title
  ✔ PASS: SlugGenerator caps slug at 80 chars on word boundary
  ✔ PASS: CaptionFormatter groups cues by pause threshold
  ✔ PASS: DurationFormatter formats seconds correctly
  ✔ PASS: MarkdownRenderer produces correct structured markdown
  ✔ PASS: StorageService deleteSummaryItem moves files to Trash
--------------------------------------------------
  Summary: 16 Passed | 0 Failed
==================================================
```

---

## License

This project is licensed under the [MIT License](LICENSE).

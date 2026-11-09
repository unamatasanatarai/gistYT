# gistYT

<p align="center">
  <img src="macos-native/Resources/AppIcon.png" width="128" height="128" alt="gistYT Logo" />
</p>

<p align="center">
  <strong>Turn any YouTube video into an actionable English brief in seconds with automated transcript extraction and Google Gemini.</strong>
  <br />
  Available as a zero-dependency native macOS AppKit desktop application and a fast, scriptable Python command-line interface.
</p>

<p align="center">
  <a href="https://github.com/unamatasanatarai/gistYT/releases"><img src="https://img.shields.io/github/v/release/unamatasanatarai/gistYT?label=release" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/macOS-12.0%2B-blue?logo=apple" alt="macOS 12.0+" />
  <img src="https://img.shields.io/badge/Swift-Native%20AppKit-F05138?logo=swift&logoColor=white" alt="Swift AppKit" />
  <img src="https://img.shields.io/badge/Python-3.14-3776AB?logo=python&logoColor=white" alt="Python 3.14" />
  <img src="https://img.shields.io/badge/Gemini-3.8%20%7C%203.6%20%7C%203.5-4285F4?logo=googlegemini&logoColor=white" alt="Google Gemini" />
  <img src="https://img.shields.io/badge/tests-132%20passing-brightgreen" alt="132 Passing Tests" />
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License" />
</p>

---

## Why gistYT

Long-form YouTube videos often bury 5 minutes of core takeaways in 45 minutes of content. Meanwhile, auto-generated subtitles are difficult to skim—lacking punctuation, cluttered with filler words, and often in other languages.

**gistYT** eliminates manual video scrubbing. It pulls video captions, sends them through Google Gemini with a strict structured schema, and produces an actionable brief in clear English. You get a clean, searchable Markdown document with key takeaways, verbatim quotes, and topic tags—ready to review in 60 seconds or archive in your personal knowledge base.

---

## Key Capabilities

### Universal Video Ingestion
Accepts any YouTube URL format—including standard `watch?v=`, short `youtu.be/`, Shorts, embeds, live streams, mobile links, or raw 11-character video IDs. Strips tracking parameters like `?si=` automatically.

### Multi-Track Caption Negotiation
Pulls subtitles using `yt-dlp` and falls back automatically to `youtube-transcript-api` if needed. Prioritizes human English subtitles first, auto-generated English second, the creator's original language third, and machine translation only as a last resort.

### Structured 5-Part Briefs
Every summary follows a consistent, predictable structure:
* **TL;DR**: A one-sentence takeaway capturing the core message.
* **Summary**: 2–4 concise paragraphs explaining what the video covers.
* **Key Points**: 5–10 chronologically organized, self-contained takeaways.
* **Notable Quotes**: Memorable verbatim quotes translated to English if necessary.
* **Topic Tags**: 3–8 concise tags for organization and categorization.

### Multi-Model Gemini Rotation
Guarantees uninterrupted generation by rotating across models:
```text
gemini-3.8-flash ──▶ gemini-3.6-flash ──▶ gemini-3.5-flash-lite ──▶ gemini-3.1-flash-lite
```
If a model is overloaded, rate-limited, returns malformed JSON, or encounters a network issue, the next model in sequence takes over automatically.

### Two Native Interfaces
* **macOS Desktop App**: Pure Swift and AppKit. Features a split-view library, live Markdown preview, quick clipboard paste (`⌘V`), Finder reveal, and local document management.
* **Command Line Interface**: Scriptable Python CLI powered by `uv`. Supports decoupled single-command runs (`./gistyt <url>`) or separate transcript fetching (`gistyt-transcript`) to review captions before spending Gemini API quota (`gistyt-summarize`).

### Local-First Plain-Text Storage
Saves all summaries as standard Markdown (`.md`) and raw transcripts as plain text (`.txt`) directly in `summaries/` and `transcriptions/` (or `~/Documents/gistYT/`). Your notes remain human-readable, searchable, and compatible with Obsidian, Notion, Logseq, and Git.

### Cookie-Authenticated Extraction
Supports extracting subtitles from age-restricted, unlisted, or membership-only videos by delegating authentication to your installed desktop browser profile (Safari, Chrome, Firefox, Brave, Edge, or Chromium).

---

## How It Works

```text
1. Provide URL ──▶ 2. Extract Transcript ──▶ 3. Gemini Rotation ──▶ 4. Markdown Brief
   (Link or ID)       (yt-dlp / API fallback)    (Strict JSON schema)     (Saved to disk)
```

1. **Provide Link**: Paste a video URL or ID in the macOS app or pass it to `./gistyt` in your terminal.
2. **Extract Captions**: The caption engine retrieves video metadata (title, channel, duration) and saves the cleanest caption stream to a `.txt` transcript.
3. **Generate Summary**: Gemini processes the transcript using structured JSON output verified against a strict Pydantic schema.
4. **Read & Archive**: The brief is displayed immediately and saved to your local library as Markdown.

---

## What Makes It Different

* **Zero Electron Overhead**: The desktop app is written in native Swift using AppKit. It launches instantly and uses minimal memory without packaging a browser runtime.
* **No Runtime Dependencies for App Users**: The macOS app bundles its own `yt-dlp` executable. You do not need to install Python, Node.js, or Homebrew to run it.
* **Decoupled Workflow**: Fetching subtitles and calling Gemini are strictly separated under the hood. You can verify whether a video has viable captions before expending LLM quota.
* **Resilient by Default**: Rather than failing on model rate limits or schema mismatches, client-side rotation ensures successful completion across four Gemini model tiers.

---

## Choose Your Interface

| Capability | macOS Native Desktop (`macos-native`) | Command Line Interface (`cli`) |
|---|:---:|:---:|
| **Platform** | macOS 12.0+ | Any OS with Python 3.14+ |
| **Technology** | Swift / AppKit | Python 3.14 / uv |
| **User Interface** | Split-view library + Markdown viewer | Terminal stdout / Markdown files |
| **One-Click Ingestion** | `⌘V` (Paste) + `Return` | `./gistyt <url>` |
| **Decoupled Fetching** | Segmented Brief/Transcript toggle | `gistyt-transcript` & `gistyt-summarize` |
| **Finder Integration** | Reveal in Finder & Move to Trash | Standard directory output |
| **Configuration** | In-app Settings Sheet (`⌘,`) | `.env` file or environment variables |

---

## Quick Start

### 1. macOS Desktop Application

1. Download **`gistYT-<version>.dmg`** from the [Latest Release](https://github.com/unamatasanatarai/gistYT/releases).
2. Open the `.dmg` and drag **gistYT** into your `/Applications` directory.
3. Open Settings (`⌘,`) and paste your [Gemini API Key](https://aistudio.google.com/apikey).

To build the macOS app from source:
```bash
cd macos-native
make build   # Compiles build/gistYT.app
make run     # Launches the application
make dmg     # Generates release DMG installer
```

### 2. Command Line Interface

Requirements: **Python 3.14+**, **[uv](https://docs.astral.sh/uv/)**, and a **Gemini API Key**.

```bash
# Navigate to the CLI directory
cd cli

# Install dependencies and sync virtual environment
uv sync

# Configure your API key
cp .env.example .env
# Set GEMINI_API_KEY="your-key-here" in .env

# Run end-to-end on any YouTube URL
./gistyt "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

#### Two-Step Inspection Workflow

```bash
# 1. Fetch transcript without calling Gemini
uv run gistyt-transcript "https://youtu.be/dQw4w9WgXcQ"

# 2. Review the saved .txt file, then summarize when ready
uv run gistyt-summarize transcriptions/rick-astley-never-gonna-give-you-up-official-video-4k-remaster.txt
```

---

## Configuration

Both interfaces support runtime customization:

| Setting | CLI Environment Variable | macOS App Setting | Default | Purpose |
|---|---|---|---|---|
| **API Key** | `GEMINI_API_KEY` | Settings Sheet | *(Required)* | Google AI Studio access key |
| **Model Rotation** | `GEMINI_MODELS` | Built-in | `gemini-3.8-flash,gemini-3.6-flash,gemini-3.5-flash-lite,gemini-3.1-flash-lite` | Ordered fallback sequence |
| **Caption Languages** | `--lang <codes>` | Settings Sheet | `en,pl,es,de,fr` | Subtitle priority order |
| **Browser Profile** | `--cookies-from-browser` | Settings Sheet | `None` | Authenticate age-gated/private videos |
| **Output Directory** | `--out-dir <dir>` | Settings Sheet | `summaries` / `~/Documents/gistYT` | Directory for Markdown briefs |

---

## Testing & Quality

The repository contains 132 automated tests that run with mocked network backends for fast, deterministic execution:

```bash
# Run the macOS Swift test suite (16 tests)
make -C macos-native test

# Run the Python CLI test suite (116 tests)
cd cli && uv run python -m pytest tests
```

---

## Release Pipeline

Release packaging across the entire repository is driven by `.release.sh` using `ggrel`:

```bash
ggrel <version>
```

The release script runs both test suites, synchronizes versions, compiles `build/gistYT-<version>.dmg`, builds the Python wheel and source distribution in `cli/dist/`, and publishes all five release artifacts to GitHub.

---

## License

This project is licensed under the [MIT License](LICENSE).

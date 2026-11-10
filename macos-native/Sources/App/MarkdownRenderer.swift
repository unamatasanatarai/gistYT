import Foundation

public enum MarkdownRenderer {
    public static func renderMarkdown(
        summary: VideoSummary,
        title: String,
        channel: String?,
        duration: String?,
        url: String,
        model: String,
        sourceFilename: String,
        date: Date = Date()
    ) -> String {
        var lines: [String] = []

        // Title
        lines.append("# \(title)")
        lines.append("")

        // Metadata line
        var metaItems: [String] = []
        if let ch = channel, !ch.isEmpty { metaItems.append(ch) }
        if let dur = duration, !dur.isEmpty { metaItems.append(dur) }
        if !url.isEmpty { metaItems.append(url) }

        if !metaItems.isEmpty {
            lines.append(metaItems.joined(separator: " · "))
            lines.append("")
        }

        // TL;DR
        let tldrBlock = "> **TL;DR** \(summary.tldr.trimmingCharacters(in: .whitespacesAndNewlines))"
        lines.append(tldrBlock)
        lines.append("")

        // Notable Quotes (Placed right under TL;DR)
        let cleanQuotes = summary.notableQuotes.compactMap { q -> String? in
            let cleaned = q.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
            return cleaned.isEmpty ? nil : cleaned
        }
        if !cleanQuotes.isEmpty {
            lines.append("## Notable quotes")
            lines.append("")
            for quote in cleanQuotes {
                lines.append("> \"\(quote)\"")
                lines.append("")
            }
        }

        // Summary
        lines.append("## Summary")
        lines.append("")
        lines.append(summary.summary.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append("")

        // Key Points
        lines.append("## Key points")
        lines.append("")
        for point in summary.keyPoints {
            let p = point.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty {
                lines.append("- \(p)")
            }
        }
        lines.append("")

        // Topics
        let cleanTopics = summary.topics.compactMap { t -> String? in
            let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        if !cleanTopics.isEmpty {
            lines.append("## Topics")
            lines.append("")
            lines.append(cleanTopics.joined(separator: " · "))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    public static func renderHTML(markdown: String) -> String {
        let jsonString: String
        if let data = try? JSONSerialization.data(withJSONObject: [markdown]),
           var str = String(data: data, encoding: .utf8) {
            // Escape every '<', not just "</": "<!--" plus "<script" inside script data
            // puts the HTML parser in the double-escaped state, so the real </script>
            // stops closing the element. JSON only contains '<' inside string literals,
            // where < is a valid escape.
            str = str.replacingOccurrences(of: "<", with: "\\u003c")
            jsonString = "\(str)[0]"
        } else {
            jsonString = "''"
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                :root {
                    --bg: #ffffff;
                    --text: #1e293b;
                    --muted: #64748b;
                    --border: #e2e8f0;
                    --tldr-bg: #f8fafc;
                    --tldr-border: #3b82f6;
                    --tldr-text: #0f172a;
                    --tldr-badge-bg: #dbeafe;
                    --tldr-badge-text: #1d4ed8;
                    --quote-bg: #f8fafc;
                    --quote-border: #cbd5e1;
                    --tag-bg: #f1f5f9;
                    --tag-border: #e2e8f0;
                    --tag-text: #475569;
                    --link: #2563eb;
                }
                @media (prefers-color-scheme: dark) {
                    :root {
                        --bg: #18181b;
                        --text: #f1f5f9;
                        --muted: #94a3b8;
                        --border: #27272a;
                        --tldr-bg: #1e293b;
                        --tldr-border: #38bdf8;
                        --tldr-text: #f8fafc;
                        --tldr-badge-bg: #0369a1;
                        --tldr-badge-text: #e0f2fe;
                        --quote-bg: #27272a;
                        --quote-border: #52525b;
                        --tag-bg: #27272a;
                        --tag-border: #3f3f46;
                        --tag-text: #cbd5e1;
                        --link: #38bdf8;
                    }
                }
                * {
                    box-sizing: border-box;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: var(--bg);
                    color: var(--text);
                    line-height: 1.7;
                    margin: 0;
                    padding: 40px 48px;
                    max-width: 720px;
                    margin-left: auto;
                    margin-right: auto;
                    font-size: 15.5px;
                    -webkit-font-smoothing: antialiased;
                }
                h1 {
                    font-size: 26px;
                    font-weight: 700;
                    letter-spacing: -0.025em;
                    line-height: 1.25;
                    margin-top: 0;
                    margin-bottom: 10px;
                    color: var(--text);
                }
                .meta {
                    color: var(--muted);
                    font-size: 13px;
                    font-weight: 400;
                    margin-bottom: 24px;
                    padding-bottom: 16px;
                    border-bottom: 1px solid var(--border);
                }
                .meta a {
                    color: var(--link);
                    text-decoration: none;
                }
                .meta a:hover {
                    text-decoration: underline;
                }
                .tldr-card {
                    background: var(--tldr-bg);
                    border: 1px solid var(--border);
                    border-left: 4px solid var(--tldr-border);
                    border-radius: 8px;
                    padding: 16px 20px;
                    margin: 22px 0 28px 0;
                    font-size: 15.5px;
                    color: var(--tldr-text);
                    font-weight: 450;
                    line-height: 1.6;
                }
                .tldr-badge {
                    display: inline-block;
                    background: var(--tldr-badge-bg);
                    color: var(--tldr-badge-text);
                    font-size: 11px;
                    font-weight: 700;
                    letter-spacing: 0.05em;
                    text-transform: uppercase;
                    padding: 2px 7px;
                    border-radius: 4px;
                    margin-right: 8px;
                    vertical-align: middle;
                }
                h2 {
                    font-size: 18px;
                    font-weight: 650;
                    letter-spacing: -0.015em;
                    margin-top: 32px;
                    margin-bottom: 12px;
                    color: var(--text);
                }
                p {
                    margin-top: 0;
                    margin-bottom: 16px;
                }
                ul {
                    margin-top: 0;
                    margin-bottom: 22px;
                    padding-left: 20px;
                }
                li {
                    margin-bottom: 8px;
                    line-height: 1.65;
                }
                blockquote {
                    background: var(--quote-bg);
                    border-left: 3px solid var(--quote-border);
                    border-radius: 4px;
                    padding: 10px 16px;
                    margin: 12px 0;
                    font-style: italic;
                    color: var(--text);
                }
                .topics-container {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 8px;
                    margin-top: 10px;
                    margin-bottom: 24px;
                }
                .topic-pill {
                    background: var(--tag-bg);
                    border: 1px solid var(--tag-border);
                    color: var(--tag-text);
                    padding: 3px 10px;
                    border-radius: 20px;
                    font-size: 12px;
                    font-weight: 500;
                }
            </style>
        </head>
        <body>
            <div id="content"></div>
            <script>
                const rawMarkdown = \(jsonString);
                
                function escapeHTML(str) {
                    return str
                        .replace(/&/g, '&amp;')
                        .replace(/</g, '&lt;')
                        .replace(/>/g, '&gt;')
                        .replace(/"/g, '&quot;')
                        .replace(/'/g, '&#39;');
                }

                function parseMarkdown(md) {
                    let html = '';
                    const lines = md.split('\\n');
                    let inList = false;
                    let isFirstMeta = true;
                    
                    for (let i = 0; i < lines.length; i++) {
                        let line = lines[i];
                        
                        if (line.startsWith('# ')) {
                            html += '<h1>' + escapeHTML(line.substring(2)) + '</h1>';
                            continue;
                        }
                        
                        if (line.startsWith('> **TL;DR**')) {
                            const text = escapeHTML(line.replace('> **TL;DR**', '').trim());
                            html += '<div class="tldr-card"><span class="tldr-badge">TL;DR</span>' + text + '</div>';
                            continue;
                        }
                        
                        if (line.startsWith('> ')) {
                            const quote = escapeHTML(line.substring(2).trim());
                            html += '<blockquote>' + quote + '</blockquote>';
                            continue;
                        }
                        
                        if (line.startsWith('## Topics')) {
                            html += '<h2>Topics</h2>';
                            if (i + 2 < lines.length && lines[i+2].includes('·')) {
                                const tags = lines[i+2].split('·').map(t => escapeHTML(t.trim())).filter(Boolean);
                                html += '<div class="topics-container">';
                                tags.forEach(t => {
                                    html += '<span class="topic-pill">' + t + '</span>';
                                });
                                html += '</div>';
                                i += 2;
                            }
                            continue;
                        }

                        if (line.startsWith('## ')) {
                            if (inList) { html += '</ul>'; inList = false; }
                            html += '<h2>' + escapeHTML(line.substring(3)) + '</h2>';
                            continue;
                        }
                        
                        if (line.startsWith('- ')) {
                            if (!inList) { html += '<ul>'; inList = true; }
                            html += '<li>' + escapeHTML(line.substring(2)) + '</li>';
                            continue;
                        } else if (inList && line.trim() === '') {
                            html += '</ul>';
                            inList = false;
                            continue;
                        }

                        if (line.includes(' · ') && isFirstMeta && line.includes('https://')) {
                            isFirstMeta = false;
                            const parts = line.split(' · ');
                            const formatted = parts.map(p => {
                                const trimmed = p.trim();
                                if (trimmed.startsWith('https://')) {
                                    const safeHref = encodeURI(trimmed);
                                    return '<a href="' + safeHref + '" target="_blank">' + escapeHTML(trimmed) + '</a>';
                                }
                                return escapeHTML(trimmed);
                            }).join(' · ');
                            html += '<div class="meta">' + formatted + '</div>';
                            continue;
                        }
                        
                        if (line.trim().length > 0) {
                            html += '<p>' + escapeHTML(line) + '</p>';
                        }
                    }
                    if (inList) { html += '</ul>'; }
                    return html;
                }
                
                document.getElementById('content').innerHTML = parseMarkdown(rawMarkdown);
            </script>
        </body>
        </html>
        """
    }
}

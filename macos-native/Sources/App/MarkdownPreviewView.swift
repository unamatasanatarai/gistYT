import SwiftUI
import WebKit

public struct MarkdownPreviewView: NSViewRepresentable {
    public let markdown: String

    public init(markdown: String) {
        self.markdown = markdown
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent background until styled
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        let html = MarkdownRenderer.renderHTML(markdown: markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }
}

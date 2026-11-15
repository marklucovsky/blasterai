// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  HelpView.swift
//  claudeBlast
//
//  Settings › Help: the guides on blasterai.app, read inside the app.
//
//  The site is where guides are written and kept up to date; the app only
//  reads them. `help/index.json` on the site says which set of guides each
//  build should read, so when a release changes the screens, older builds can
//  keep a frozen copy that matches them while the main guides move on. Cache
//  headers on the site make a page the device has seen open at once, and
//  offline.
//
//  Nothing identifying is sent: plain GETs for public pages, no cookies of
//  ours, no query string beyond what the site's own links carry.
//

import SwiftUI
import WebKit

/// One guide in a set's `index.json`.
struct HelpGuide: Decodable, Identifiable, Hashable {
    let slug: String
    let title: String
    let summary: String
    let path: String
    var id: String { slug }
}

/// The site's `help/index.json`: which guide set each build reads.
struct HelpManifest: Decodable {
    struct GuideSet: Decodable {
        let fromBuild: Int
        var toBuild: Int?
        let index: String
    }
    let sets: [GuideSet]

    /// The first set whose build range holds `build`.
    func set(for build: Int) -> GuideSet? {
        sets.first { build >= $0.fromBuild && build <= ($0.toBuild ?? .max) }
    }
}

enum HelpSite {
    static let base = URL(string: "https://blasterai.app")!
    static let manifest = base.appending(path: "help/index.json")

    /// This build's number, as the manifest counts them.
    static var build: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    static func url(_ path: String) -> URL {
        URL(string: path, relativeTo: base)?.absoluteURL ?? base
    }

    /// Fetch, falling back to whatever the cache holds when the network
    /// cannot answer, so Help still opens offline once it has been seen.
    static func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let decoder = JSONDecoder()
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            let cached = URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad)
            let (data, _) = try await URLSession.shared.data(for: cached)
            return try decoder.decode(T.self, from: data)
        }
    }
}

struct HelpView: View {
    @State private var guides: [HelpGuide] = []
    @State private var failed = false

    var body: some View {
        List {
            if failed {
                Section {
                    Text("Can't reach the guides right now.")
                        .foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }
                }
            } else if guides.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Section {
                    ForEach(guides) { guide in
                        NavigationLink {
                            GuidePage(url: HelpSite.url(guide.path), title: guide.title)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(guide.title)
                                Text(guide.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            Section {
                Link("Open the Guides on the Web", destination: HelpSite.base.appending(path: "guides/"))
                Link("Questions and Answers", destination: HelpSite.base.appending(path: "faq/"))
                Link("Email Support", destination: URL(string: "mailto:support@blasterai.app")!)
            }
        }
        .navigationTitle("Help")
        .task { if guides.isEmpty { await load() } }
        .refreshable { await load() }
    }

    private func load() async {
        failed = false
        do {
            let manifest = try await HelpSite.fetch(HelpManifest.self, from: HelpSite.manifest)
            guard let set = manifest.set(for: HelpSite.build) else { failed = true; return }
            struct Index: Decodable { let guides: [HelpGuide] }
            guides = try await HelpSite.fetch(Index.self, from: HelpSite.url(set.index)).guides
        } catch {
            failed = guides.isEmpty
        }
    }
}

/// One guide, drawn as one of the app's own pages: the site marks itself
/// `in-app` (no site header or footer, system font, light or dark with the
/// device). Links to other blasterai.app pages stay here; anything else opens
/// in Safari.
struct GuidePage: View {
    let url: URL
    let title: String

    @State private var pageTitle: String?
    @State private var state: GuideWebView.LoadState = .loading
    @State private var reload = 0

    var body: some View {
        ZStack {
            GuideWebView(url: url, reload: reload, state: $state, pageTitle: $pageTitle)
                .opacity(state == .failed ? 0 : 1)
            switch state {
            case .loading:
                ProgressView()
            case .failed:
                VStack(spacing: 12) {
                    Text("Can't reach this guide right now.").foregroundStyle(.secondary)
                    Button("Try Again") { reload += 1 }
                }
            case .loaded:
                EmptyView()
            }
        }
        .navigationTitle(pageTitle ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: url)
            }
        }
    }
}

struct GuideWebView: UIViewRepresentable {
    enum LoadState { case loading, loaded, failed }

    let url: URL
    let reload: Int
    @Binding var state: LoadState
    @Binding var pageTitle: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Mark the page before it draws, so the site chrome never flashes.
        config.userContentController.addUserScript(WKUserScript(
            source: "document.documentElement.classList.add('in-app');",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        context.coordinator.load(url, in: web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if reload != context.coordinator.lastReload {
            context.coordinator.lastReload = reload
            context.coordinator.load(url, in: web)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: GuideWebView
        var lastReload = 0
        /// Set after a network failure, so the retry reads the cache first.
        private var triedCache = false

        init(_ parent: GuideWebView) { self.parent = parent }

        func load(_ url: URL, in web: WKWebView) {
            triedCache = false
            parent.state = .loading
            web.load(URLRequest(url: url))
        }

        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let target = action.request.url else { return decisionHandler(.cancel) }
            if target.scheme == "https", target.host() == HelpSite.base.host() {
                decisionHandler(.allow)
            } else {
                // Elsewhere on the web, or mail: not ours to draw.
                if action.navigationType == .linkActivated { UIApplication.shared.open(target) }
                decisionHandler(.cancel)
            }
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            parent.state = .loaded
            // "Board layout — BlasterAI guides" → "Board layout".
            if let title = web.title, !title.isEmpty {
                parent.pageTitle = title.components(separatedBy: " — ").first
            }
        }

        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            failed(web)
        }

        func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed(web)
        }

        /// Offline: try the copy the cache holds before giving up.
        private func failed(_ web: WKWebView) {
            if !triedCache, let url = web.url ?? URL(string: parent.url.absoluteString) {
                triedCache = true
                web.load(URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad))
            } else {
                parent.state = .failed
            }
        }
    }
}

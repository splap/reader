import Foundation
import OSLog
import ReaderCore
import SwiftUI

public struct ReaderView: View {
    private static let logger = Logger(subsystem: "com.example.reader", category: "reader")
    @StateObject private var model: ReaderViewModel
    private let contentInsets = UIEdgeInsets(top: 32, left: 24, bottom: 32, right: 24)

    public init(chapter: Chapter = SampleChapter.make()) {
        _model = StateObject(wrappedValue: ReaderViewModel(chapter: chapter))
    }

    public init(epubURL: URL, maxSections: Int = .max) {
        do {
            let chapter = try EPUBLoader().loadChapter(from: epubURL, maxSections: maxSections)
#if DEBUG
            Self.logger.debug(
                "Loaded EPUB \(epubURL.lastPathComponent, privacy: .public) length=\(chapter.attributedText.length, privacy: .public)"
            )
#endif
            _model = StateObject(wrappedValue: ReaderViewModel(chapter: chapter))
        } catch {
#if DEBUG
            Self.logger.error("Failed to load EPUB: \(error.localizedDescription, privacy: .public)")
#endif
            _model = StateObject(wrappedValue: ReaderViewModel(chapter: SampleChapter.make()))
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            let availableSize = CGSize(
                width: max(1, proxy.size.width - contentInsets.left - contentInsets.right),
                height: max(1, proxy.size.height - contentInsets.top - contentInsets.bottom)
            )
            ZStack {
                if let textStorage = model.textStorage,
                   let layoutManager = model.layoutManager,
                   !model.pages.isEmpty {
                    TabView(selection: $model.currentPageIndex) {
                        ForEach(model.pages.indices, id: \.self) { index in
                            Group {
                                if abs(index - model.currentPageIndex) <= 2 {
                                    ZStack(alignment: .topTrailing) {
                                        PageTextView(
                                            page: model.pages[index],
                                            textStorage: textStorage,
                                            layoutManager: layoutManager,
                                            onSendToLLM: { selection in
                                                model.llmPayload = LLMPayload(selection: selection)
                                            }
                                        )
#if DEBUG
                                        PageRangeOverlay(
                                            pageIndex: index,
                                            page: model.pages[index],
                                            layoutManager: model.layoutManager
                                        )
                                        .padding(8)
#endif
                                    }
                                    .frame(
                                        width: availableSize.width,
                                        height: availableSize.height,
                                        alignment: .topLeading
                                    )
                                    .padding(EdgeInsets(
                                        top: contentInsets.top,
                                        leading: contentInsets.left,
                                        bottom: contentInsets.bottom,
                                        trailing: contentInsets.right
                                    ))
                                } else {
                                    Color.clear
                                }
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .onChange(of: model.currentPageIndex) { newIndex in
                        model.updateCurrentPage(newIndex)
                    }
                } else {
                    ProgressView("Preparing pages...")
                }
#if DEBUG
                DebugOverlay(
                    pages: model.pages,
                    textStorage: model.textStorage,
                    currentPage: model.currentPageIndex
                )
#endif
            }
            .onAppear {
                model.updateLayout(pageSize: proxy.size, insets: contentInsets)
            }
            .onChange(of: proxy.size) { newSize in
                model.updateLayout(pageSize: newSize, insets: contentInsets)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.settingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(item: $model.llmPayload) { payload in
            LLMModalView(payload: payload)
        }
        .sheet(isPresented: $model.settingsPresented) {
            ReaderSettingsView(fontScale: Binding(
                get: { model.fontScale },
                set: { model.updateFontScale($0) }
            ))
        }
    }
}

#if DEBUG
private struct PageRangeOverlay: View {
    let pageIndex: Int
    let page: Page
    let layoutManager: NSLayoutManager?

    @State private var actualRange: NSRange = NSRange(location: 0, length: 0)

    var body: some View {
        let planned = page.range
        let isEmpty = actualRange.length == 0

        VStack(alignment: .trailing, spacing: 2) {
            Text("page \(pageIndex)")
            Text("planned \(planned.location) + \(planned.length)")
            Text("actual \(actualRange.location) + \(actualRange.length)")
                .foregroundStyle(isEmpty ? Color.red : Color.green)
        }
        .font(.caption2)
        .foregroundStyle(.white)
        .padding(6)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .allowsHitTesting(false)
        .onAppear(perform: updateActualRange)
        .onChange(of: page.range.location) { _ in updateActualRange() }
        .onChange(of: page.range.length) { _ in updateActualRange() }
    }

    private func updateActualRange() {
        guard let layoutManager else {
            actualRange = NSRange(location: 0, length: 0)
            return
        }
        actualRange = page.actualCharacterRange(using: layoutManager)
    }
}

private struct DebugOverlay: View {
    let pages: [Page]
    let textStorage: NSTextStorage?
    let currentPage: Int

    var body: some View {
        let textLength = textStorage?.length ?? 0
        let wordsOnPage = wordCountForCurrentPage()

        VStack(alignment: .leading, spacing: 4) {
            Text("pages: \(pages.count)")
            Text("text length (chars): \(textLength)")
            Text("current page: \(currentPage)")
            Text("words on page: \(wordsOnPage)")
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(8)
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    private func wordCountForCurrentPage() -> Int {
        guard let textStorage,
              currentPage >= 0,
              currentPage < pages.count else {
            return 0
        }
        let range = pages[currentPage].range
        let text = (textStorage.string as NSString).substring(with: range)
        return countWords(in: text)
    }

    private func countWords(in text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord {
                    count += 1
                    inWord = true
                }
            } else {
                inWord = false
            }
        }
        return count
    }
}
#endif

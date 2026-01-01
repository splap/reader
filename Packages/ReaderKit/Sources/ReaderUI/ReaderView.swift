import ReaderCore
import SwiftUI

public struct ReaderView: View {
    @StateObject private var model: ReaderViewModel
    private let contentInsets = UIEdgeInsets(top: 32, left: 24, bottom: 32, right: 24)

    public init(chapter: Chapter = SampleChapter.make()) {
        _model = StateObject(wrappedValue: ReaderViewModel(chapter: chapter))
    }

    public var body: some View {
        GeometryReader { proxy in
            let availableSize = CGSize(
                width: max(1, proxy.size.width - contentInsets.left - contentInsets.right),
                height: max(1, proxy.size.height - contentInsets.top - contentInsets.bottom)
            )
            ZStack {
                if let textStorage = model.textStorage, !model.pages.isEmpty {
                    TabView(selection: $model.currentPageIndex) {
                        ForEach(model.pages.indices, id: \.self) { index in
                            Group {
                                if abs(index - model.currentPageIndex) <= 2 {
                                    PageTextView(
                                        page: model.pages[index],
                                        textStorage: textStorage,
                                        onSendToLLM: { selection in
                                            model.llmPayload = LLMPayload(selection: selection)
                                        }
                                    )
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

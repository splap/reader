import ReaderCore
import SwiftUI

struct LLMPayload: Identifiable {
    let id = UUID()
    let selection: SelectionPayload
}

struct LLMModalView: View {
    let payload: LLMPayload
    @State private var followUpText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected Text")
                            .font(.headline)
                        Text(payload.selection.selectedText)
                            .font(.body)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Answer")
                            .font(.headline)
                        Text("Stub answer. LLM integration is wired next.")
                            .font(.body)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Follow-up")
                            .font(.headline)
                        TextField("Ask a follow-up", text: $followUpText)
                            .textFieldStyle(.roundedBorder)
                        Button("Send") {}
                            .buttonStyle(.bordered)
                            .disabled(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Context")
                            .font(.headline)
                        Text(payload.selection.contextText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Ask")
        }
    }
}

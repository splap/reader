import SwiftUI

struct ReaderSettingsView: View {
    @Binding var fontScale: CGFloat

    var body: some View {
        NavigationStack {
            Form {
                Section("Font Size") {
                    HStack {
                        Text("A")
                            .font(.caption)
                        Slider(value: Binding(
                            get: { Double(fontScale) },
                            set: { fontScale = CGFloat($0) }
                        ), in: 0.8...1.6, step: 0.05)
                        Text("A")
                            .font(.title3)
                    }
                    Text(String(format: "%.2fx", fontScale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

import SwiftUI

struct ReaderSettingsView: View {
    @Binding var fontScale: CGFloat
    @State private var sliderValue: CGFloat

    init(fontScale: Binding<CGFloat>) {
        self._fontScale = fontScale
        self._sliderValue = State(initialValue: fontScale.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Font Size") {
                    HStack {
                        Text("A")
                            .font(.caption)
                        Slider(
                            value: $sliderValue,
                            in: 1.25...2.0,
                            step: 0.05,
                            onEditingChanged: { editing in
                                if !editing {
                                    // Only update when user stops dragging
                                    fontScale = sliderValue
                                }
                            }
                        )
                        Text("A")
                            .font(.title3)
                    }
                    Text(String(format: "%.1fx", sliderValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

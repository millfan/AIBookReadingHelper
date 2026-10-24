import SwiftUI
import VisionKit

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @State private var selectedText = ""
    @State private var isAnalyzing = false

    var body: some View {
        VStack(spacing: 0) {
            if let image = camera.capturedImage {
                HSplitView {
                    page(image)
                        .frame(minWidth: 420)
                    SelectionPanel(selectedText: selectedText, isAnalyzing: isAnalyzing)
                        .frame(minWidth: 240, idealWidth: 300)
                }
            } else {
                ZStack {
                    Color.black
                    switch camera.status {
                    case .idle, .running:
                        CameraPreviewView(session: camera.session)
                    case .unauthorized:
                        notice("Camera access is turned off. Turn it on in System Settings > Privacy & Security > Camera, then reopen the app.")
                    case .unavailable:
                        notice("No camera was found.")
                    }
                }
            }

            Divider()

            HStack {
                if let errorMessage = camera.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                Spacer()
                if camera.capturedImage == nil {
                    Button("Capture page", systemImage: "camera") {
                        camera.capturePage()
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(camera.status != .running)
                } else {
                    Button("Retake", systemImage: "arrow.counterclockwise") {
                        selectedText = ""
                        camera.retake()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding()
        }
        .frame(minWidth: 760, minHeight: 520)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder
    private func page(_ image: NSImage) -> some View {
        if ImageAnalyzer.isSupported {
            LiveTextImageView(image: image, selectedText: $selectedText, isAnalyzing: $isAnalyzing)
                .background(Color.black)
        } else {
            ZStack {
                Color.black
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                notice("Live Text isn't available on this Mac, so text on the page can't be selected.")
            }
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding()
    }
}

/// The side panel that shows what is selected on the page. Translation is added next to it in a later step.
private struct SelectionPanel: View {
    let selectedText: String
    let isAnalyzing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected text")
                .font(.headline)
            if isAnalyzing {
                ProgressView("Finding text on the page…")
                    .controlSize(.small)
            } else if selectedText.isEmpty {
                Text("Drag across a word, phrase or sentence on the page to select it.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(selectedText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
        }
        .padding()
    }
}

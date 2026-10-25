import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @State private var selectedText = ""
    @State private var isAnalyzing = false
    @AppStorage(SettingsKey.rotateCamera) private var rotateCamera = false
    /// The HTML file shown in place of the camera, if one has been opened.
    @State private var htmlURL: URL?
    @State private var isChoosingHTML = false
    @State private var htmlErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // The side panel stays put while the left side switches between the live camera and the captured page.
            // The left side takes 75% of the window's width and the panel the rest.
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    leftPane
                        .frame(width: geometry.size.width * 0.75, height: geometry.size.height)
                    Divider()
                    SelectionPanel(selectedText: selectedText, isAnalyzing: isAnalyzing)
                        .frame(maxWidth: .infinity)
                }
            }

            Divider()

            HStack {
                if let errorMessage = htmlErrorMessage ?? camera.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Open HTML…", systemImage: "doc.richtext") {
                    isChoosingHTML = true
                }
                .keyboardShortcut("o", modifiers: .command)
                if htmlURL != nil {
                    Button("Back to camera", systemImage: "camera") {
                        closeHTML()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                } else if camera.capturedImage == nil {
                    // For a camera that sees the book upside down. Captured pages are turned too, so Live Text reads them.
                    Toggle(isOn: $rotateCamera) {
                        Label("Rotate 180°", systemImage: "rotate.right")
                    }
                    .toggleStyle(.button)
                    .disabled(camera.status != .running)
                    Button("Capture page", systemImage: "camera") {
                        camera.capturePage(rotated180: rotateCamera)
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
        .frame(minWidth: 960, minHeight: 520)
        .fileImporter(isPresented: $isChoosingHTML, allowedContentTypes: [.html]) { result in
            switch result {
            case .success(let url):
                openHTML(url)
            case .failure(let error):
                htmlErrorMessage = error.localizedDescription
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    /// An opened HTML file, the captured page once one has been taken, or else the live camera.
    @ViewBuilder
    private var leftPane: some View {
        if let htmlURL {
            HTMLDocumentView(url: htmlURL, selectedText: $selectedText)
        } else if let image = camera.capturedImage {
            page(image)
        } else {
            ZStack {
                Color.black
                switch camera.status {
                case .idle, .running:
                    CameraPreviewView(session: camera.session, rotated180: rotateCamera)
                case .unauthorized:
                    notice("Camera access is turned off. Turn it on in System Settings > Privacy & Security > Camera, then reopen the app.")
                case .unavailable:
                    notice("No camera was found.")
                }
            }
        }
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

    private func openHTML(_ url: URL) {
        closeHTML()
        // The file picker grants sandboxed access to the file only while it is being accessed.
        guard url.startAccessingSecurityScopedResource() else {
            htmlErrorMessage = "The app wasn't allowed to open \(url.lastPathComponent)."
            return
        }
        htmlURL = url
    }

    private func closeHTML() {
        htmlURL?.stopAccessingSecurityScopedResource()
        htmlURL = nil
        htmlErrorMessage = nil
        selectedText = ""
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding()
    }
}

/// The side panel that shows what is selected on the page and its translation.
private struct SelectionPanel: View {
    let selectedText: String
    let isAnalyzing: Bool
    @AppStorage(SettingsKey.engine) private var engine = TranslationEngine.apple
    @AppStorage(SettingsKey.direction) private var direction = TranslationDirection.englishToChinese

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected text")
                .font(.headline)
            Group {
                if isAnalyzing {
                    ProgressView("Finding text on the page…")
                        .controlSize(.small)
                } else if selectedText.isEmpty {
                    Text("Drag across a word, phrase or sentence on the page to select it.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(selectedText)
                            .font(.readingText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Divider()

            Text("Translation")
                .font(.headline)
            Text("\(direction.source.name) to \(direction.target.name) with \(engine.menuTitle) · change both in the View menu")
                .font(.caption)
                .foregroundStyle(.secondary)
            TranslationView(text: selectedText,
                            engine: engine,
                            direction: direction)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding()
    }
}

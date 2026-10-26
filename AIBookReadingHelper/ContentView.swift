import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @State private var selectedText = ""
    @State private var isAnalyzing = false
    @AppStorage(SettingsKey.rotateCamera) private var rotateCamera = false
    /// Turned off with the Camera button. The camera is also off while a file is open.
    @AppStorage(SettingsKey.cameraEnabled) private var cameraEnabled = true
    /// How much of the window's width the left side takes, set by dragging the divider.
    @AppStorage(SettingsKey.leftPaneFraction) private var leftFraction = 0.75
    /// The HTML or PDF file shown in place of the camera, if one has been opened.
    @State private var documentURL: URL?
    @State private var isChoosingDocument = false
    @State private var documentErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // The side panel stays put while the left side switches between the camera, a captured page and an opened file.
            // The left side starts at 75% of the window's width; dragging the divider changes that.
            GeometryReader { geometry in
                let leftWidth = clampedLeftWidth(geometry.size.width * leftFraction, in: geometry.size.width)
                HStack(spacing: 0) {
                    leftPane
                        .frame(width: leftWidth, height: geometry.size.height)
                    PaneDivider { location in
                        leftFraction = clampedLeftWidth(location, in: geometry.size.width) / geometry.size.width
                    }
                    SelectionPanel(selectedText: selectedText, isAnalyzing: isAnalyzing)
                        .frame(maxWidth: .infinity)
                }
                .coordinateSpace(.named(PaneDivider.coordinateSpace))
            }

            Divider()

            HStack {
                if let errorMessage = documentErrorMessage ?? camera.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Open File…", systemImage: "doc.richtext") {
                    isChoosingDocument = true
                }
                .keyboardShortcut("o", modifiers: .command)
                Toggle(isOn: $cameraEnabled) {
                    Label("Camera", systemImage: cameraEnabled ? "video" : "video.slash")
                }
                .toggleStyle(.button)
                .help(cameraEnabled ? "Turn the camera off" : "Turn the camera on")
                if documentURL != nil {
                    Button("Back to camera", systemImage: "camera") {
                        closeDocument()
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
        .fileImporter(isPresented: $isChoosingDocument, allowedContentTypes: [.html, .pdf]) { result in
            switch result {
            case .success(let url):
                openDocument(url)
            case .failure(let error):
                documentErrorMessage = error.localizedDescription
            }
        }
        // Runs again whenever the camera is turned on or off, or a file is opened or closed.
        .task(id: cameraShouldRun) {
            if cameraShouldRun {
                await camera.start()
            } else {
                camera.stop()
            }
        }
        .onDisappear { camera.stop() }
    }

    /// The camera runs only while it is turned on and no file is open.
    private var cameraShouldRun: Bool {
        cameraEnabled && documentURL == nil
    }

    /// An opened HTML or PDF file, the captured page once one has been taken, or else the live camera.
    @ViewBuilder
    private var leftPane: some View {
        if let documentURL {
            if UTType(filenameExtension: documentURL.pathExtension)?.conforms(to: .pdf) == true {
                PDFDocumentView(url: documentURL, selectedText: $selectedText)
            } else {
                HTMLDocumentView(url: documentURL, selectedText: $selectedText)
            }
        } else if let image = camera.capturedImage {
            page(image)
        } else {
            ZStack {
                Color.black
                if !cameraEnabled {
                    notice("The camera is off. Click Camera to turn it on.")
                } else {
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

    /// Keeps both sides usable: at least 420 points on the left and 240 for the panel.
    private func clampedLeftWidth(_ width: CGFloat, in totalWidth: CGFloat) -> CGFloat {
        min(max(width, 420), max(totalWidth - 240, 420))
    }

    private func openDocument(_ url: URL) {
        closeDocument()
        // The file picker grants sandboxed access to the file only while it is being accessed.
        guard url.startAccessingSecurityScopedResource() else {
            documentErrorMessage = "The app wasn't allowed to open \(url.lastPathComponent)."
            return
        }
        documentURL = url
    }

    private func closeDocument() {
        documentURL?.stopAccessingSecurityScopedResource()
        documentURL = nil
        documentErrorMessage = nil
        selectedText = ""
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding()
    }
}

/// The line between the left side and the side panel. Dragging it reports the pointer's position across the window.
private struct PaneDivider: View {
    static let coordinateSpace = "panes"
    let onDrag: (CGFloat) -> Void

    var body: some View {
        Divider()
            // A wider invisible strip makes the one-point line easy to grab.
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
                            .onChanged { onDrag($0.location.x) }
                    )
            }
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

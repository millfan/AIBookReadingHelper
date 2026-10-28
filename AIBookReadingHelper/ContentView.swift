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
    /// Whether the reader is typing in the selected text area, where Space and Esc must type rather than act as shortcuts.
    @State private var isEditingSelection = false
    /// Whether the Internet view is showing in place of the camera.
    @State private var isShowingWeb = false
    /// Whether the reader is typing in the Internet view's address box.
    @State private var isTypingAddress = false
    /// Whether the side panel shows ChatGPT instead of the selected text and translation.
    @AppStorage(SettingsKey.showOpenAI) private var showOpenAI = false
    /// Set once ChatGPT has been shown, so it stays loaded, and signed in, while the normal panel is showing.
    @State private var hasShownOpenAI = false
    /// Whether the reader is typing in ChatGPT.
    @State private var isTypingInOpenAI = false

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
                    sidePanel
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
                Toggle(isOn: $showOpenAI) {
                    Label("OpenAI view", systemImage: "bubble.left.and.bubble.right")
                }
                .toggleStyle(.button)
                .help(showOpenAI ? "Show the selected text and translation" : "Show ChatGPT in the side panel")
                Button("Ask ChatGPT", systemImage: "arrow.up.forward.app") {
                    OpenAIView.askInBrowser(selectedText)
                }
                .help("Open ChatGPT in your web browser, where you are signed in, with the selected text")
                .disabled(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !isShowingWeb {
                    Button("Internet", systemImage: "globe") {
                        closeDocument()
                        isShowingWeb = true
                    }
                    .keyboardShortcut("l", modifiers: .command)
                }
                Toggle(isOn: $cameraEnabled) {
                    Label("Camera", systemImage: cameraEnabled ? "video" : "video.slash")
                }
                .toggleStyle(.button)
                .help(cameraEnabled ? "Turn the camera off" : "Turn the camera on")
                if documentURL != nil || isShowingWeb {
                    Button("Back to camera", systemImage: "camera") {
                        closeDocument()
                    }
                    .keyboardShortcut(isTyping ? nil : KeyboardShortcut(.escape, modifiers: []))
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
                    .keyboardShortcut(isTyping ? nil : KeyboardShortcut(.space, modifiers: []))
                    .disabled(camera.status != .running)
                } else {
                    Button("Retake", systemImage: "arrow.counterclockwise") {
                        selectedText = ""
                        camera.retake()
                    }
                    .keyboardShortcut(isTyping ? nil : KeyboardShortcut(.escape, modifiers: []))
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

    /// The camera runs only while it is turned on and no file or web page is showing.
    private var cameraShouldRun: Bool {
        cameraEnabled && documentURL == nil && !isShowingWeb
    }

    /// While the reader types in the panel or the address box, Space and Esc type there instead of acting as shortcuts.
    private var isTyping: Bool {
        isEditingSelection || isTypingAddress || (showOpenAI && isTypingInOpenAI)
    }

    /// The selected text and translation, or ChatGPT. ChatGPT is kept loaded once shown, just hidden,
    /// so switching back to it doesn't reload the page or lose a conversation.
    private var sidePanel: some View {
        ZStack {
            SelectionPanel(selectedText: $selectedText, isAnalyzing: isAnalyzing, isEditing: $isEditingSelection)
                .opacity(showOpenAI ? 0 : 1)
                .allowsHitTesting(!showOpenAI)
            if showOpenAI || hasShownOpenAI {
                OpenAIView(selectedText: selectedText, isShowing: showOpenAI, isTyping: $isTypingInOpenAI)
                    .opacity(showOpenAI ? 1 : 0)
                    .allowsHitTesting(showOpenAI)
            }
        }
        .onChange(of: showOpenAI, initial: true) {
            if showOpenAI {
                hasShownOpenAI = true
            }
        }
    }

    /// An opened HTML or PDF file, the Internet view, the captured page once one has been taken, or else the live camera.
    @ViewBuilder
    private var leftPane: some View {
        if let documentURL {
            if UTType(filenameExtension: documentURL.pathExtension)?.conforms(to: .pdf) == true {
                PDFDocumentView(url: documentURL, selectedText: $selectedText)
            } else {
                HTMLDocumentView(url: documentURL, selectedText: $selectedText)
            }
        } else if isShowingWeb {
            WebBrowserView(selectedText: $selectedText, isTypingAddress: $isTypingAddress)
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
        isShowingWeb = false
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

/// A line between two panes that can be dragged. It reports the pointer's position in `coordinateSpace`:
/// across it for panes side by side, or down it for stacked panes.
private struct PaneDivider: View {
    static let coordinateSpace = "panes"
    var stacked = false
    var coordinateSpace = Self.coordinateSpace
    let onDrag: (CGFloat) -> Void

    var body: some View {
        Divider()
            // A wider invisible strip makes the one-point line easy to grab.
            .overlay {
                Color.clear
                    .frame(width: stacked ? nil : 9, height: stacked ? 9 : nil)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            (stacked ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpace))
                            .onChanged { onDrag(stacked ? $0.location.y : $0.location.x) }
                    )
            }
    }
}

/// The side panel that shows what is selected on the page and its translation.
private struct SelectionPanel: View {
    @Binding var selectedText: String
    let isAnalyzing: Bool
    @Binding var isEditing: Bool
    @AppStorage(SettingsKey.engine) private var engine = TranslationEngine.apple
    @AppStorage(SettingsKey.direction) private var direction = TranslationDirection.englishToChinese
    /// What is selected inside the panel's own copy of the selected text.
    @State private var panelSelection = ""
    /// How much of the panel's height the selected text takes, set by dragging the line under it.
    @AppStorage(SettingsKey.selectedTextFraction) private var selectedTextFraction = 0.25
    private static let coordinateSpace = "panel"

    /// The word to look up: one selected in the panel, or else the page's selection when it is a single word.
    private var dictionaryWord: String? {
        WordDictionary.singleWord(in: panelSelection) ?? WordDictionary.singleWord(in: selectedText)
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            // Both parts fill the panel's width and keep their headings at the top left, whatever they show,
            // so the Translation heading stays put when there is nothing to translate.
            VStack(alignment: .leading, spacing: 0) {
                selectedTextSection
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: clampedTopHeight(height * selectedTextFraction, in: height), alignment: .topLeading)
                PaneDivider(stacked: true, coordinateSpace: Self.coordinateSpace) { location in
                    guard height > 0 else { return }
                    selectedTextFraction = clampedTopHeight(location, in: height) / height
                }
                translationSection
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .coordinateSpace(.named(Self.coordinateSpace))
        }
        .padding()
        .onChange(of: selectedText) {
            panelSelection = ""
        }
    }

    /// Keeps both parts usable: at least 80 points for the selected text and 160 for the translation.
    private func clampedTopHeight(_ height: CGFloat, in totalHeight: CGFloat) -> CGFloat {
        min(max(height, 80), max(totalHeight - 160, 80))
    }

    private var selectedTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected text / paste")
                .font(.headline)
            Group {
                if isAnalyzing {
                    ProgressView("Finding text on the page…")
                        .controlSize(.small)
                } else {
                    // Text can also be typed or pasted here to translate it.
                    // Selecting a word here looks it up in the dictionary. The page keeps its own selection meanwhile.
                    SelectableTextView(editing: $selectedText,
                                       font: .systemFont(ofSize: NSFont.systemFontSize * 2),
                                       selection: $panelSelection,
                                       isFocused: $isEditing)
                        .overlay(alignment: .topLeading) {
                            if selectedText.isEmpty {
                                Text("Drag across a word, phrase or sentence on the page to select it, or paste text here.")
                                    .foregroundStyle(.secondary)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Translation")
                .font(.headline)
            Text("\(direction.source.name) to \(direction.target.name) with \(engine.menuTitle) · change both in the View menu")
                .font(.caption)
                .foregroundStyle(.secondary)
            // The dictionary definition of a single word follows the translation in the same view.
            TranslationView(text: selectedText,
                            engine: engine,
                            direction: direction,
                            dictionaryWord: dictionaryWord)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @State private var selectedText = ""
    @State private var isAnalyzing = false
    @AppStorage(SettingsKey.rotateCamera) private var rotateCamera = false
    /// Turned off with the Camera button. The camera is also off while the Internet or File view is showing.
    @AppStorage(SettingsKey.cameraEnabled) private var cameraEnabled = true
    /// How much of the window's width the left side takes, set by dragging the divider.
    @AppStorage(SettingsKey.leftPaneFraction) private var leftFraction = 0.75
    /// Which view the left side shows: the camera, a web page or an opened file. Remembered, so the app opens in it.
    @AppStorage(SettingsKey.leftView) private var leftView = LeftView.camera
    /// The HTML or PDF file shown in the File view, if one has been opened. It stays open while another view is showing.
    @State private var documentURL: URL?
    /// Where the last opened file is, kept so the File view shows it again after the app is reopened.
    @AppStorage(SettingsKey.documentBookmark) private var documentBookmark = Data()
    /// How large the File view shows its page, changed with Cmd+ and Cmd− from the View menu.
    @AppStorage(SettingsKey.pageZoom) private var zoom = PageZoom.normal
    @State private var isChoosingDocument = false
    @State private var documentErrorMessage: String?
    /// Whether the reader is typing in the selected text area, where Space and Esc must type rather than act as shortcuts.
    @State private var isEditingSelection = false
    /// A picture of the web page, taken with Capture text, for pages such as Kindle's whose text can't be selected.
    /// Live Text finds the words in it.
    @State private var webSnapshot: NSImage?
    @State private var webSnapshotRequest = 0
    /// Whether the reader is typing in the Internet view's address box.
    @State private var isTypingAddress = false
    /// Whether the side panel shows the selected text and translation, ChatGPT or Google Translate.
    @AppStorage(SettingsKey.sidePanel) private var sidePanel = SidePanel.normal
    /// Set once ChatGPT has been shown, so it stays loaded, and signed in, while another panel is showing.
    @State private var hasShownOpenAI = false
    /// Set once Google Translate has been shown, so it stays loaded while another panel is showing.
    @State private var hasShownGoogleTranslate = false
    /// Whether the reader is typing in ChatGPT.
    @State private var isTypingInOpenAI = false
    /// Whether the reader is typing in Google Translate.
    @State private var isTypingInGoogleTranslate = false
    /// Set once Notes has been shown, so it stays loaded, and a document stays open, while another panel is showing.
    @State private var hasShownNotes = false
    /// Whether the reader is typing in Notes.
    @State private var isTypingInNotes = false

    var body: some View {
        VStack(spacing: 0) {
            // The side panel stays put while the left side switches between the camera, a web page and an opened file.
            // The left side starts at 75% of the window's width; dragging the divider changes that.
            GeometryReader { geometry in
                let leftWidth = clampedLeftWidth(geometry.size.width * leftFraction, in: geometry.size.width)
                HStack(spacing: 0) {
                    leftPane
                        .frame(width: leftWidth, height: geometry.size.height)
                    PaneDivider { location in
                        leftFraction = clampedLeftWidth(location, in: geometry.size.width) / geometry.size.width
                    }
                    sidePanelView
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
                // One button steps through the views: Camera, then Internet, then File. It has a fixed width, and the
                // view's own buttons sit in a space as wide as the widest set, so it doesn't move when switching views.
                Button {
                    switchLeftView(to: leftView.next)
                } label: {
                    Label(leftView.title, systemImage: leftView.systemImage)
                        .frame(width: 120)
                }
                .help("Switch to the \(leftView.next.title)")
                ZStack(alignment: .leading) {
                    widestViewControls
                        .hidden()
                        .disabled(true)
                    HStack {
                        switch leftView {
                        case .camera:
                            cameraControls
                        case .internet:
                            if webSnapshot == nil {
                                Button("Capture text", systemImage: "text.viewfinder") {
                                    webSnapshotRequest += 1
                                }
                                .help("Take a picture of the page and select its text with Live Text, for pages whose text can't be selected, such as Kindle books")
                            } else {
                                Button("Back to page", systemImage: "arrow.uturn.backward") {
                                    selectedText = ""
                                    webSnapshot = nil
                                }
                                .keyboardShortcut(isTyping ? nil : KeyboardShortcut(.escape, modifiers: []))
                            }
                        case .file:
                            Button("Open File…", systemImage: "doc.richtext") {
                                isChoosingDocument = true
                            }
                            .keyboardShortcut("o", modifiers: .command)
                        }
                    }
                }
                // Steps the side panel through the selected text and translation, ChatGPT and Google Translate.
                Button {
                    sidePanel = sidePanel.next
                } label: {
                    Label(sidePanel.title, systemImage: sidePanel.systemImage)
                        .frame(width: 130)
                }
                .help("Switch the side panel to \(sidePanel.next.title)")
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
        // Runs again whenever the camera is turned on or off, or another view is chosen.
        .task(id: cameraShouldRun) {
            if cameraShouldRun {
                await camera.start()
            } else {
                camera.stop()
            }
        }
        .onAppear(perform: reopenLastDocument)
        .onDisappear { camera.stop() }
    }

    /// The camera runs only while it is turned on and the Camera view is showing.
    private var cameraShouldRun: Bool {
        cameraEnabled && leftView == .camera
    }

    /// Stands in for the widest set of a view's buttons, the Camera view's, to keep their space the same width.
    private var widestViewControls: some View {
        HStack {
            Toggle("Camera", systemImage: "video", isOn: .constant(true))
                .toggleStyle(.button)
            Toggle("Rotate 180°", systemImage: "rotate.right", isOn: .constant(false))
                .toggleStyle(.button)
            Button("Capture page", systemImage: "camera") {}
        }
    }

    /// The Camera view's buttons: the camera on and off, then rotating and capturing, or retaking a captured page.
    @ViewBuilder
    private var cameraControls: some View {
        Toggle(isOn: $cameraEnabled) {
            Label("Camera", systemImage: cameraEnabled ? "video" : "video.slash")
        }
        .toggleStyle(.button)
        .help(cameraEnabled ? "Turn the camera off" : "Turn the camera on")
        if camera.capturedImage == nil {
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

    /// While the reader types in the panel or the address box, Space and Esc type there instead of acting as shortcuts.
    private var isTyping: Bool {
        isEditingSelection || isTypingAddress
            || (sidePanel == .openAI && isTypingInOpenAI)
            || (sidePanel == .googleTranslate && isTypingInGoogleTranslate)
            || (sidePanel == .notes && isTypingInNotes)
    }

    /// The selected text and translation, ChatGPT, Google Translate or Notes. The web panels are kept loaded once shown,
    /// just hidden, so switching back to them doesn't reload the page or lose a conversation or a note.
    private var sidePanelView: some View {
        ZStack {
            SelectionPanel(selectedText: $selectedText, isAnalyzing: isAnalyzing, isEditing: $isEditingSelection)
                .opacity(sidePanel == .normal ? 1 : 0)
                .allowsHitTesting(sidePanel == .normal)
            if sidePanel == .openAI || hasShownOpenAI {
                OpenAIView(selectedText: selectedText, isShowing: sidePanel == .openAI, isTyping: $isTypingInOpenAI)
                    .opacity(sidePanel == .openAI ? 1 : 0)
                    .allowsHitTesting(sidePanel == .openAI)
            }
            if sidePanel == .googleTranslate || hasShownGoogleTranslate {
                GoogleTranslateView(selectedText: selectedText, isShowing: sidePanel == .googleTranslate,
                                    isTyping: $isTypingInGoogleTranslate)
                    .opacity(sidePanel == .googleTranslate ? 1 : 0)
                    .allowsHitTesting(sidePanel == .googleTranslate)
            }
            if sidePanel == .notes || hasShownNotes {
                NotesView(isTyping: $isTypingInNotes)
                    .opacity(sidePanel == .notes ? 1 : 0)
                    .allowsHitTesting(sidePanel == .notes)
            }
        }
        .onChange(of: sidePanel, initial: true) {
            switch sidePanel {
            case .openAI: hasShownOpenAI = true
            case .googleTranslate: hasShownGoogleTranslate = true
            case .notes: hasShownNotes = true
            case .normal: break
            }
        }
    }

    /// The opened HTML or PDF file, a web page, or the camera: the captured page once one has been taken, or else the
    /// live camera.
    @ViewBuilder
    private var leftPane: some View {
        switch leftView {
        case .file:
            if let documentURL {
                if UTType(filenameExtension: documentURL.pathExtension)?.conforms(to: .pdf) == true {
                    PDFDocumentView(url: documentURL, selectedText: $selectedText, zoom: zoom)
                } else {
                    HTMLDocumentView(url: documentURL, selectedText: $selectedText, zoom: zoom)
                }
            } else {
                ZStack {
                    Color.black
                    notice("Click Open File to open an HTML or PDF file.")
                }
            }
        case .internet:
            // The page stays loaded behind its picture, so going back to it doesn't reload it.
            ZStack {
                WebBrowserView(selectedText: $selectedText, isTypingAddress: $isTypingAddress,
                               snapshotRequest: webSnapshotRequest) { image in
                    selectedText = ""
                    webSnapshot = image
                }
                .opacity(webSnapshot == nil ? 1 : 0)
                .allowsHitTesting(webSnapshot == nil)
                if let webSnapshot {
                    page(webSnapshot)
                }
            }
        case .camera:
            cameraPane
        }
    }

    @ViewBuilder
    private var cameraPane: some View {
        if let image = camera.capturedImage {
            page(image)
        } else {
            ZStack {
                Color.black
                if !cameraEnabled {
                    notice("The camera is off. Click Camera to turn it on.")
                } else {
                    switch camera.status {
                    case .idle:
                        // The preview waits for the camera to start: a preview made for the empty session at launch
                        // stays black.
                        ProgressView()
                            .controlSize(.small)
                    case .running:
                        CameraPreviewView(previewLayer: camera.previewLayer, rotated180: rotateCamera)
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
    /// Rounded to whole points: a side panel that starts partway through a pixel draws its web pages blurred.
    private func clampedLeftWidth(_ width: CGFloat, in totalWidth: CGFloat) -> CGFloat {
        min(max(width, 420), max(totalWidth - 240, 420)).rounded()
    }

    private func openDocument(_ url: URL) {
        documentURL?.stopAccessingSecurityScopedResource()
        documentURL = nil
        documentErrorMessage = nil
        selectedText = ""
        // The file picker grants sandboxed access to the file only while it is being accessed.
        guard url.startAccessingSecurityScopedResource() else {
            documentErrorMessage = "The app wasn't allowed to open \(url.lastPathComponent)."
            return
        }
        documentURL = url
        documentBookmark = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                  relativeTo: nil)) ?? Data()
    }

    /// Opens the file that was open when the app was last used, if it is still there.
    private func reopenLastDocument() {
        guard documentURL == nil, !documentBookmark.isEmpty else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: documentBookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            // The file was moved away or deleted.
            documentBookmark = Data()
            return
        }
        documentURL = url
        // The file was moved or renamed, so the bookmark is saved again to keep finding it.
        if isStale, let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                          includingResourceValuesForKeys: nil, relativeTo: nil) {
            documentBookmark = bookmark
        }
    }

    private func switchLeftView(to view: LeftView) {
        leftView = view
        webSnapshot = nil
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

/// The views the left side switches between.
enum LeftView: String {
    case camera
    case internet
    case file

    var title: String {
        switch self {
        case .camera: "Camera view"
        case .internet: "Internet view"
        case .file: "File view"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: "camera"
        case .internet: "globe"
        case .file: "doc.richtext"
        }
    }

    /// The view the switch button goes to next.
    var next: LeftView {
        switch self {
        case .camera: .internet
        case .internet: .file
        case .file: .camera
        }
    }
}

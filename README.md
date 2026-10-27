# AIBookReadingHelper

A macOS app for reading physical books in another language. Point the Mac's camera at a page, capture it, select a word, phrase or sentence on the photo, and see its translation on screen. HTML and PDF files can be opened and translated the same way.

## Status

- [x] Step 1: Live FaceTime camera preview and page capture
- [x] Step 2: Select text on the captured page (Live Text)
- [x] Step 3: Translate the selection (Apple Translation or Google Cloud Translation)

## Running it

1. Open `AIBookReadingHelper.xcodeproj` in Xcode 16 or later.
2. Choose the **AIBookReadingHelper** scheme and **My Mac** as the destination, then press **Cmd+R**.
3. Allow camera access when macOS asks.

The app needs macOS 14 or later. Apple Translation needs macOS 15 or later.

The app is signed with a free Apple Development certificate (Personal Team `H95KCGR5JM`). A stable signature lets macOS remember the camera permission across rebuilds. To build it under another Apple ID, choose your own team under **Signing & Capabilities**.

## Installing it as an app

Run `scripts/make-dmg.sh` from the project folder. It builds a Release copy and creates `dist/AIBookReadingHelper.dmg`. Open the DMG and drag **AIBookReadingHelper** onto **Applications**. The app is signed with the Personal Team, so it runs on Macs signed in to the same Apple ID.

The app icon is drawn in `design/AppIcon.svg`. Its PNG sizes are in `AIBookReadingHelper/Assets.xcassets/AppIcon.appiconset`.

## Using it

- **Space** or **Capture page** takes a photo of the page in front of the camera.
- Drag across a word, phrase or sentence on the captured page to select it. The selection appears in the panel on the right.
- The translation appears under the selection. **Copy** puts it on the clipboard.
- Select a word in the panel's copy of the selection to see its definition from the macOS Dictionary under the translation, laid out with its pronunciation, parts of speech, numbered senses and sections. A single word selected on the page is looked up too. Chinese words need a Chinese dictionary turned on in the Dictionary app's Settings.
- Clicking or selecting in the panel leaves the selection on the page as it is. Only a click on the page itself clears it.
- **Esc** or **Retake** goes back to the live camera.
- Drag the line between the left side and the panel to resize them. The app remembers where you leave it.
- Drag the line between the selected text and the translation to resize them. The selected text starts at a quarter of the panel's height.
- **Open File…** (Cmd+O) shows an HTML or PDF file in place of the camera. Select text in it to translate it, just like a captured page. **Back to camera** (Esc) closes it. For HTML, only the file itself is opened, so images or styles stored next to it may not show. For PDF, only files with real text can be selected; a scanned PDF made of pictures has no text to pick.
- **Camera** turns the camera on and off. The app remembers your choice. The camera also turns off by itself while an HTML or PDF file is open, and comes back on with **Back to camera** if it was on.
- **Rotate 180°**, next to **Capture page**, turns the camera picture upside down, for when the camera sees the book upside down. Captured pages are turned too, so their text can still be selected.

## Translation

Choose the direction from the **View** menu: **ENG → CHN** (English to Simplified Chinese, the default) or **CHN → ENG**.

Choose the engine from the **View** menu too:

- **Apple Translation** (the default) runs on the Mac and needs no account. The first time you use a language, macOS asks to download it.
- **Google Translation** uses the Google Cloud Translation API. Create an API key for the Cloud Translation API in the Google Cloud console, then paste it into **AI Book Reading Helper > Settings…** (Cmd+,). The key is kept in the app's preferences on this Mac.

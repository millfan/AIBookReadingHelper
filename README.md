# AIBookReadingHelper

A macOS app for reading physical books in another language. Point the Mac's camera at a page, capture it, select a word, phrase or sentence on the photo, and see its translation on screen.

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

## Using it

- **Space** or **Capture page** takes a photo of the page in front of the camera.
- Drag across a word, phrase or sentence on the captured page to select it. The selection appears in the panel on the right.
- The translation appears under the selection.
- **Esc** or **Retake** goes back to the live camera.
- **View > Rotate Camera 180°** (Shift+Cmd+R) turns the camera picture upside down, for when the camera sees the book upside down. Captured pages are turned too, so their text can still be selected.

## Translation

Choose the direction from the **View** menu: **ENG → CHN** (English to Simplified Chinese, the default) or **CHN → ENG**.

Choose the engine from the **View** menu too:

- **Apple Translation** (the default) runs on the Mac and needs no account. The first time you use a language, macOS asks to download it.
- **Google Translation** uses the Google Cloud Translation API. Create an API key for the Cloud Translation API in the Google Cloud console, then paste it into **AI Book Reading Helper > Settings…** (Cmd+,). The key is kept in the app's preferences on this Mac.

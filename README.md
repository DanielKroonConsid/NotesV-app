# NotesV

NotesV is a macOS note-taking app that turns a few meeting bullet points into a full meeting protocol. Add a meeting from an `.ics` file, jot down short notes, and an AI provider of your choice expands them into a structured protocol that you can keep editing.

The app looks and behaves like Apple's Notes app. It needs no Microsoft 365 account or sign-in.

## Features

- **Notes like on a Mac:** three-column layout, text styles, lists, checklists, tables, pinned notes and full-text search. Rich text can be pasted from Apple Notes.
- **Meetings from `.ics` files:** click or drag a file onto the meeting field, or enter the details by hand. The note list groups notes by meeting day, and notes without a meeting are shown first.
- **Meeting protocols:** a protocol covers meeting info, attendees, agenda and discussion, decisions and action items. Before it is created, you confirm who attended and match action items with owners.
- **Protocols as attachments:** each protocol is stored as its own note and linked to the note it was made from. It opens in its own window, can be copied to an email and can be marked as sent.
- **Any OpenAI-compatible server:** OpenAI, Azure OpenAI, OpenRouter, Ollama, LM Studio or any other base URL. With Ollama or LM Studio, meeting data stays on your Mac.
- **Plain Markdown files:** each note is one `.md` file with YAML front matter, readable in any Markdown editor.
- **Your own storage folder:** keep the notes in the app's container, or pick a folder, for example one that the OneDrive app syncs.
- **Swedish and English:** the app is available in both languages. Protocols are written in the language of your notes unless you pick one.

## Tech stack

| Area | Choice |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI, with AppKit where needed |
| Rich-text editor | `NSTextView` wrapped in `NSViewRepresentable` |
| Platform | macOS 15 Sequoia or later |
| Meetings | `.ics` files, read by the app's own parser |
| AI | Any OpenAI-compatible API, called directly with `URLSession` |
| Storage | GitHub Flavored Markdown files with YAML front matter |
| Secrets | macOS Keychain |
| Tests | Swift Testing |

The project uses Apple frameworks only and has no third-party dependencies.

## Run the app on a Mac

### Requirements

- A Mac with macOS 15 Sequoia or later
- Xcode 16 or later
- An Apple ID added to Xcode, for signing the app (a free Personal Team works)
- An API key for an AI provider, or a local server such as [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai). You only need this to generate protocols.

### Run from Xcode

1. Clone the repository and open the project:

   ```bash
   git clone https://github.com/DanielKroonConsid/NotesV-app.git
   ```

   ```bash
   open NotesV-app/NotesV.xcodeproj
   ```

2. Select the **NotesV** target and open **Signing & Capabilities**.
3. Choose your own **Team**. If Xcode can't register the bundle identifier, change it to one of your own, for example `com.yourname.NotesV`.
4. Choose **My Mac** as the destination and press **⌘R**.

### Build from the command line

Choose your team in Xcode first, as described above. Then run this from the repository folder:

```bash
xcodebuild -project NotesV.xcodeproj -scheme NotesV -destination 'platform=macOS' -derivedDataPath build/DerivedData -allowProvisioningUpdates build
```

```bash
open build/DerivedData/Build/Products/Debug/NotesV.app
```

### Set up an AI provider

1. Open **NotesV → Settings** (⌘,) and choose the **AI** tab.
2. Pick a preset, or enter a base URL.
3. Enter your API key. Local servers such as Ollama and LM Studio don't need one.
4. Keep the model on **Latest**, or pick a specific one, and test the connection.

API keys are stored only in the macOS Keychain. Unless you use a local server, meeting details and notes are sent to the server you choose.

### Run the tests

```bash
xcodebuild -project NotesV.xcodeproj -scheme NotesV -destination 'platform=macOS' -derivedDataPath build/DerivedData -allowProvisioningUpdates test
```

The tests use mocked responses and never call a real AI service.

## Project structure

| Path | Content |
|---|---|
| `NotesV/UI/` | SwiftUI views, the text editor and Settings |
| `NotesV/Domain/` | Note, meeting and protocol models, the Markdown codec and the `.ics` parser |
| `NotesV/Services/` | Storage, Keychain and protocol generation |
| `NotesV/Resources/` | Assets and the String Catalog with all UI text |
| `NotesVTests/` | Unit tests |
| `Config/` | Info.plist, entitlements and the script that draws the app icon |
| `documents/` | Build plan and progress notes, in Swedish |

## Platform support

NotesV is **macOS only**. A PC (Windows) version is not on the roadmap, and neither are iOS or other platforms.

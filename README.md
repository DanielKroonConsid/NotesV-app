# NotesV

NotesV is a macOS note-taking app that turns a few meeting bullet points into a full meeting protocol. Add a meeting from an `.ics` file, jot down short notes, and an AI provider of your choice expands them into a structured protocol that you can keep editing.

NotesV is a native Mac app and needs no Microsoft 365 account or sign-in.

## Features

- **Rich notes:** three-column layout, text styles, lists, checklists, tables, pinned notes and full-text search. Rich text can be pasted from other apps.
- **Meetings from `.ics` files:** click or drag a file onto the meeting field, or enter the details by hand. The note list groups notes by meeting day, and notes without a meeting are shown first.
- **Meeting protocols:** a protocol covers meeting info, attendees, agenda and discussion, decisions and action items. Before it is created, you confirm who attended and match action items with owners.
- **Protocols as attachments:** each protocol is stored as its own note and linked to the note it was made from. It opens in its own window, can be copied to an email and can be marked as sent.
- **Tasks:** NotesV finds the checkboxes in your protocols and shows how many are new. You set the owner and due date before a task is added, and you can add tasks of your own.
- **Task overview:** tabs for your tasks, other people's, all, a backlog of tasks for later and completed tasks. Sort by due date, meeting or owner, and open the protocol a task came from. Tasks can have a note and subtasks. See the [task guide](documents/Uppgifter.md), in Swedish.
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

## Download

Download the latest `.dmg` from [Releases](https://github.com/DanielKroonConsid/NotesV-app/releases), open it and drag NotesV to **Applications**. NotesV needs macOS 15 Sequoia or later. There are no automatic updates, so new versions are downloaded the same way.

Pre-releases aren't notarized by Apple, so macOS blocks them the first time:

1. Open NotesV. macOS says it can't verify the app. Choose **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to **Security** and choose **Open Anyway** next to NotesV.
4. Confirm with your password or Touch ID.

Only do this for a file you downloaded from this repository. To check the file, compare its checksum with the `.sha256` file on the release page:

```bash
shasum -a 256 ~/Downloads/NotesV-*.dmg
```

## Build from source

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
| `documents/` | Build plan, progress notes and the task guide, in Swedish |

## Make a release

Pushing a version tag builds, tests and publishes a release with GitHub Actions:

```bash
git tag v0.1.0
```

```bash
git push origin v0.1.0
```

Without Apple credentials, the release is signed ad hoc and marked as a pre-release. To notarize releases, add these repository secrets. They need a paid Apple Developer Program membership.

| Secret | Content |
|---|---|
| `DEVELOPER_ID_IDENTITY` | The certificate's name, for example `Developer ID Application: Name (TEAMID)` |
| `DEVELOPER_ID_CERT_BASE64` | The certificate as a `.p12` file, Base64 encoded |
| `DEVELOPER_ID_CERT_PASSWORD` | The password of the `.p12` file |
| `NOTARY_KEY_BASE64` | An App Store Connect API key (`.p8`), Base64 encoded |
| `NOTARY_KEY_ID` | The key's id |
| `NOTARY_ISSUER_ID` | The key's issuer id |

To build a release locally, run `Config/build-release.sh 0.1.0`. The result ends up in `build/release`.

## Platform support

NotesV is **macOS only**. A PC (Windows) version is not on the roadmap, and neither are iOS or other platforms.

## License

Copyright © 2026 Daniel Kroon. All rights reserved. See [LICENSE](LICENSE).

NotesV is an independent project. It is not affiliated with or endorsed by Apple Inc.

# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project overview

**NotesV** is a macOS note-taking app that turns a few meeting bullet points into a full meeting protocol.
The user adds a meeting from an `.ics` file, jots down short notes, and an AI provider expands them into a
structured protocol.

**No Microsoft Entra app.** NotesV can't be registered in Microsoft Entra, so nothing may depend on one: no MSAL sign-in, no Microsoft Graph, no Outlook calendar and no Microsoft 365 Copilot.

- **Look and feel:** a native Mac note-taking app that follows Apple's Human Interface Guidelines. NotesV has its own identity, and its icon and texts must not be confused with Apple's products or imply a connection to Apple.
- **Platform:** **macOS only**. No Windows, iOS or cross-platform targets.
- **Languages:** the UI is available in **Swedish and English**. Protocols are generated in the language of the user's notes unless the user picks one.
- **Audience:** anyone on a Mac. The app needs no Microsoft 365 account or sign-in.

## Tech stack

| Area | Choice |
|---|---|
| App | Swift, SwiftUI, AppKit where needed |
| Minimum OS | **macOS 15 Sequoia** |
| Rich-text editor | `NSTextView` wrapped in `NSViewRepresentable` (SwiftUI's rich-text `TextEditor` needs macOS 26) |
| Meetings | `.ics` files, read by `Domain/ICSParser` |
| AI / protocol generation | Any **OpenAI-compatible API** (OpenAI, Azure OpenAI, OpenRouter, Ollama, LM Studio…), selectable by the user |
| Storage | **Markdown files** in the app's container, or in a **folder the user picks** in Settings |

Don't add third-party dependencies without asking first. Prefer Apple frameworks.
Call OpenAI-compatible APIs directly with `URLSession` (`Services/AI/OpenAICompatibleClient`) rather than adding an SDK.

## Core features

### 1. Pick a meeting
Meetings come from **`.ics` files**. The meeting field in the toolbar takes an `.ics` file, by click or drag and drop. A form in its popover corrects the details and covers meetings without a file. The details are stored on the note (`Note.meeting`).
- Read the **title, date/time, location, organizer, attendees and description**.
- Leave out attendees who declined, and rooms. Remove Outlook's Teams join block, so links and passcodes never reach the AI provider.
- Treat `.ics` files as untrusted plain text. They often come from other people.

### 2. Take notes
The editor has these features:
- **Three-column layout:** folders sidebar, then the note list, then the editor (`NavigationSplitView`).
- **Text styles:** Title, Heading, Subheading, Body, Monostyled. Bold, italic, underline, strikethrough.
- **Lists:** bulleted, dashed and numbered lists, plus **checklists** you can tick off.
- **Tables**, **pinned notes** and **full-text search**.
- **Note list:** note folders group notes by meeting day, latest first. Notes without meeting details come first, under a clear warning. Other folders and search group by modified date.
- **Paste from Apple Notes:** rich text on the clipboard becomes a note (`UI/Editor/RichPasteImporter`). Paragraph styles are worked out from font sizes and lists, and images are left out.
- Use system fonts (SF Pro), system colors and native controls so the app follows light/dark mode and accessibility settings.
- Use the standard Mac keyboard shortcuts for text styles (e.g. ⇧⌘T Title, ⇧⌘H Heading, ⇧⌘J Subheading, ⇧⌘B Body, ⇧⌘L Checklist, ⇧⌘7 bulleted list).

### 3. Generate the meeting protocol
Input: the meeting details plus the user's bullet points. Output: a formatted note with these sections:
1. **Meeting info:** title, date/time, location/link, organizer
2. **Attendees:** present and absent
3. **Agenda & discussion:** a summary for each agenda item
4. **Decisions:** a clear list
5. **Action items:** a checklist with owner and an optional due date.

Before the protocol is created, the user confirms in a dialog who attended and matches action items with owners. Anyone not ticked as attending is listed as absent.

The protocol is an **attachment** to the note it was made from:
- It is stored as its own note in the **Meeting Protocols** folder, linked by `sourceNote` in the front matter. The source note is never changed.
- Only protocols can be marked as sent. Sent protocols are listed in the Sent view, and the file stays in its folder. A `sent:` value on an ordinary note is ignored.
- The source note lists its protocols above the editor. Clicking one opens it in its own window, where it can be edited and is saved automatically.

The generated protocol must use the app's own rich-text styles (headings, lists, checklists), so the user can keep editing it like any other note.
Never invent decisions, owners or dates that aren't in the input. A missing owner gets a clear placeholder; a missing due date is simply left out.
Every AI provider must produce the same structure. Ask for structured output (e.g. JSON matching a shared schema) and convert it to rich text in the app, rather than relying on each server's free-text formatting.

### 4. Follow up tasks
The **Tasks** view in the sidebar collects the checkboxes in all protocols, sent ones included.
- The app finds unticked checkboxes on its own, locally, and shows how many are new. Nothing is added until the user has reviewed it: they edit the task, choose themselves, someone else or no owner, and set a due date. They can leave a task for later or ignore it.
- `ActionItemLine` and `DueDateParser` only fill in suggestions, and a date that can't be read is never guessed.
- The overview filters on mine and others, sorts by due date, meeting or owner, and shows the protocol of the selected task.
- Tasks are stored in the protocol's front matter (`tasks`). `source` is the checkbox line and is how a checkbox is matched to its task. Changing a task doesn't change the protocol's text.
- A task's done state follows its checkbox in both directions. If the line is gone, the task's own `status` applies.
- Tasks of a deleted protocol leave the overview, and come back if it is restored.
- The user can also write **manual tasks**, which have no protocol. They are stored in the front matter of `Manual Tasks/Tasks.md` in the root (`Note.manualTaskListID`). That folder isn't shown in the sidebar, and its note isn't listed or searched as a note.
- A task can have a **note** and **subtasks**. They belong to the task only: they aren't in the protocol's text, in Copy for Email or sent to the AI provider. A task and its subtasks are ticked independently.
- The overview has the tabs Mine, Others, All, Backlog and Completed. A task in the first three is open and not in the backlog.
- **Backlog** tasks are for later and have no due date, so moving a task there removes its date (`backlog: true`).
- Ticking a task moves it to Completed, and unticking it returns it to its tab.

## Storage

### Location
Notes are stored through `StorageService`. **App folders map to directories**, and **each note is one `.md` file**.

`Notes`, `Meeting Protocols`, `Manual Tasks` and `Recently Deleted` are in the root. **Folders the user creates are inside `Notes`**, one level deep, and `Notes` itself can't be renamed or deleted. `LocalStorageService` moves folders it finds next to `Notes` into it on every load, and a merge never loses a note.

By default they are in the app's container. In Settings the user can pick a folder with the system folder picker, for example one the OneDrive app syncs. That app handles sync and offline copies, and NotesV never talks to OneDrive itself.
- The notes go in a `NotesV` subfolder of the picked folder, so other contents never show up as note folders.
- `StorageSettings` saves a security-scoped bookmark, so the folder survives restarts and renames. If the folder is gone, the app uses the container and asks the user to pick a new one.
- Changing folder copies the notes. The old files are kept, and a note that already exists in the new folder is left as it is.
- `settings.json` in the root of the notes folder holds a copy of the AI server, the model choice and the user's names (`SettingsFile`, `SettingsBackup`), so a new Mac can get them back. It never holds API keys. The folder can be shared, so the app only reads the file after showing the user the server address and getting their OK.
- Changes made outside the app are never overwritten. `LocalStorageService` compares a hash of the file before saving and throws `changedOutsideApp`. `NoteStore` then keeps both versions as separate notes. Files are read again when the app becomes active.

### Markdown format
Notes are stored as **GitHub Flavored Markdown** with YAML front matter for metadata.
The editor converts between rich text and Markdown. Keep that conversion in one place (`Domain/MarkdownCodec`) and cover it with round-trip tests.

| Notes style | Markdown |
|---|---|
| Title | `# ` |
| Heading | `## ` |
| Subheading | `### ` |
| Body | plain paragraph |
| Monostyled | fenced code block (```` ``` ````) |
| Bold / italic / strikethrough | `**…**` / `*…*` / `~~…~~` |
| Underline | `<u>…</u>` (Markdown has no native underline) |
| Bulleted / dashed / numbered list | `* ` / `- ` / `1. ` |
| Checklist | `- [ ] ` / `- [x] ` |
| Table | GFM pipe table |

Example front matter:

```yaml
---
id: 3F2504E0-4F89-11D3-9A0C-0305E82C3301
created: 2026-10-20T09:00:00Z
modified: 2026-10-20T09:45:00Z
pinned: false
sourceNote: 7B1C2D3E-1111-4222-8333-944455566677   # Only on protocols: the note it is attached to
sent: 2026-10-20T11:00:00Z   # Only on protocols the user marked as sent
tasks:                       # Only on protocols: the reviewed tasks. `status` is open, done or ignored
  - source: "Send the offer – Ada Ek, Friday"
    task: "Send the offer"
    owner: "Ada Ek"
    mine: false
    due: 2026-10-23
    note: "Waiting for a price from Bo"
    subtasks: ["[x] Get the price", "[ ] Write a draft"]
    status: open
meeting:
  subject: "Weekly sync"
  start: 2026-10-20T09:00:00Z
  end: 2026-10-20T10:00:00Z
  location: "Room 1"
  organizer: "Ada Ek"
  attendees: ["Ada Ek", "Bo Berg"]
  agenda: "Release\nBudget"
---
```

- File names: a sanitized version of the note title plus `.md`, with a suffix like ` (2)` on conflicts. The `id` in the front matter is the stable identity, not the file name.
- Files must stay readable and editable in any Markdown editor.

## AI providers

All protocol generation goes through a single `ProtocolGenerator` protocol, so another provider can be added without changing the rest of the app:

- **`OpenAIProtocolGenerator`**: works with **any OpenAI-compatible server** through its Chat Completions API (`GET {base URL}/models`, `POST {base URL}/chat/completions`).
  - The user picks a preset (OpenAI, Azure OpenAI, OpenRouter, Ollama, LM Studio) or enters any base URL. The key is sent as `Authorization: Bearer` or, for Azure, `api-key`.
  - **The API key is optional for local servers** (Ollama, LM Studio). **Plain `http` is only allowed for `localhost`, `127.0.0.1` and `*.local`**; everything else must use `https`. The ATS exception for this lives in `Config/NotesV-Info.plist` (`NSAllowsLocalNetworking`).
  - Ask for structured output with `response_format: json_schema` (`MeetingProtocol.jsonSchema`). If the server answers 400, fall back to `json_object`, then to plain text with the schema in the prompt, and extract the JSON from the answer.
  - **Default model: always the latest.** At runtime, read the server's models list, keep only text/chat models, and pick the newest by `created`. If the server doesn't report `created`, use its only model, or ask the user to choose one when there are several. Cache the result for a day per server. Never hard-code a model name as the default.
  - If the model lookup fails, use the last cached model and show a warning.
  - Settings lets the user override this with a specific model.
  - Tell the user in the UI where meeting data is sent: outside their Microsoft 365 tenant, or, for a local server, to this Mac only.

Settings:
- A **Settings** pane (SwiftUI `Settings` scene) lets the user:
  - choose the server (preset or base URL) and how the key is sent
  - enter or remove the API key
  - choose the model ("Latest" by default) and test the connection
  - pick the storage folder
  - enter the names the user goes by, which pre-select them when reviewing tasks
- Remember the server, the model choice, the user's names and the folder's bookmark in `UserDefaults`. The rest of the app depends only on `ProtocolGenerator`, never on a concrete provider.

## Releases

Pushing a tag like `v0.1.0` makes `.github/workflows/release.yml` test the app, run `Config/build-release.sh` and publish a `.dmg` on GitHub. Without the Developer ID secrets, the release is signed ad hoc and marked as a pre-release. `Config/NotesV-Release.entitlements` must match the capabilities in the Xcode project.

## Security and secrets

- **AI API keys:** store them **only in the macOS Keychain** (one per preset, via `KeychainService`). Never in `UserDefaults`, files, logs or source code, and never in the notes folder or `settings.json`.
- Never commit API keys or other secrets.

## Architecture guidelines

- Keep the app split into clear layers:
  - `UI/`: SwiftUI views, the `NSTextView` editor wrapper, and Settings
  - `Domain/`: note, folder, meeting and protocol models, `MarkdownCodec`, `ICSParser`, and formatting logic
  - `Services/`: `StorageService`, `KeychainService`, `ProtocolGenerator` and its implementations
- Use protocols for services so they can be mocked in tests and previews.
- Use Swift Concurrency (`async/await`, `@MainActor` for UI state) and the Observation framework (`@Observable`).
- All user-facing strings go in a String Catalog (`Localizable.xcstrings`) with **Swedish and English**. No hard-coded UI text.

## Coding conventions

- Follow the Swift API Design Guidelines. Use SwiftLint/swift-format defaults if added.
- Prefer small views and computed properties over large view bodies.
- Write unit tests (Swift Testing) for the domain logic, Markdown round-trips, protocol formatting and service parsing, using mocked OpenAI responses (`MockTransport` replaces `HTTPTransport`). Tests must never call the real APIs.
- Code, comments and commit messages are in **English**.

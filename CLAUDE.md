# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project overview

**NotesV** is a macOS note-taking app that turns a few meeting bullet points into a full meeting protocol.
The user picks a meeting from their Outlook calendar, the app reads the meeting details from Microsoft 365,
the user jots down short notes, and an AI provider expands them into a structured protocol.

- **Look and feel:** as close to Apple's **Notes app on macOS** as possible: layout, typography, formatting and behaviour.
- **Platform:** **macOS only**. No Windows, iOS or cross-platform targets.
- **Languages:** the UI is available in **Swedish and English**. Protocols are generated in the language of the user's notes unless the user picks one.
- **Audience:** a **multi-tenant** app that works for any Microsoft 365 organization.

## Tech stack

| Area | Choice |
|---|---|
| App | Swift, SwiftUI, AppKit where needed |
| Minimum OS | **macOS 15 Sequoia** |
| Rich-text editor | `NSTextView` wrapped in `NSViewRepresentable` (SwiftUI's rich-text `TextEditor` needs macOS 26) |
| Auth | MSAL for macOS (Microsoft Entra ID), multi-tenant (`organizations` authority) |
| M365 data | Microsoft Graph REST API |
| AI / protocol generation | **Microsoft 365 Copilot** (default) or any **OpenAI-compatible API** (alternative: OpenAI, Azure OpenAI, OpenRouter, Ollama, LM Studio…), selectable by the user |
| Storage | **Markdown files** in a **OneDrive folder the user picks** in Settings |

Don't add third-party dependencies without asking first. Prefer Apple frameworks and the official Microsoft SDKs.
Call OpenAI-compatible APIs directly with `URLSession` (`Services/AI/OpenAICompatibleClient`) rather than adding an SDK.

## Core features

### 1. Pick a meeting from Outlook
- List the user's upcoming and recent meetings from their calendar (Graph `/me/calendarView`).
- When a meeting is picked, read its **subject, date/time, organizer, attendees (required and optional) and body/agenda**.
- Scope: **calendar event details only**. No Teams transcripts, sending email or other M365 sources unless asked.

### 2. Take notes (Mac Notes UX)
Replicate these Notes features:
- **Three-column layout:** folders sidebar, then the note list, then the editor (`NavigationSplitView`).
- **Text styles:** Title, Heading, Subheading, Body, Monostyled. Bold, italic, underline, strikethrough.
- **Lists:** bulleted, dashed and numbered lists, plus **checklists** you can tick off.
- **Tables**, **pinned notes** and **full-text search**.
- Use system fonts (SF Pro), system colors and native controls so the app follows light/dark mode and accessibility settings like Notes does.
- Mirror Notes' keyboard shortcuts (e.g. ⇧⌘T Title, ⇧⌘H Heading, ⇧⌘J Subheading, ⇧⌘B Body, ⇧⌘L Checklist, ⇧⌘7 bulleted list).

### 3. Generate the meeting protocol
Input: the meeting details plus the user's bullet points. Output: a formatted note with these sections:
1. **Meeting info:** title, date/time, location/link, organizer
2. **Attendees:** present and absent
3. **Agenda & discussion:** a summary for each agenda item
4. **Decisions:** a clear list
5. **Action items:** a checklist with owner and due date

The generated protocol must use the app's own rich-text styles (headings, lists, checklists), so the user can keep editing it like any other note.
Never invent decisions, owners or dates that aren't in the input. Leave a clear placeholder instead.
Both AI providers must produce the same structure. Ask for structured output (e.g. JSON matching a shared schema) and convert it to rich text in the app, rather than relying on each provider's free-text formatting.

## Storage

### Location
- The user picks a **root folder in their OneDrive** in Settings, using a folder picker backed by Graph (`/me/drive`).
- Save the folder's drive item ID, not just its path, so a rename doesn't break it. If the folder is gone, ask the user to pick a new one.
- **App folders map to OneDrive subfolders** under the root folder. **Each note is one `.md` file.**
- Keep a local cache so the app stays usable and fast offline. Sync when the user is back online. Changes made to the files outside the app must be detected and handled (e.g. via the drive item's eTag), not overwritten silently.

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
meeting:
  eventId: AAMkAG…        # Graph event ID, if the note is tied to a meeting
  subject: Weekly sync
  start: 2026-10-20T09:00:00Z
---
```

- File names: a sanitized version of the note title plus `.md`, with a suffix like ` (2)` on conflicts. The `id` in the front matter is the stable identity, not the file name.
- Files must stay readable and editable in any Markdown editor.

## AI providers

All protocol generation goes through a single `ProtocolGenerator` protocol with one implementation per provider:

- **`CopilotProtocolGenerator`** (default): uses **the Copilot that comes with standard Microsoft 365 business plans** (e.g. Business Basic), through the user's M365 sign-in, with no extra Copilot add-on license.
  - Before building this, check the current Microsoft docs to confirm an API exists for that tier. As far as we know, Microsoft's Copilot APIs have so far needed the paid **Microsoft 365 Copilot** license. If that's still true, stop and ask the user before going further.
  - If Copilot isn't available to a user or tenant, show a clear message and offer to switch to OpenAI.
- **`OpenAIProtocolGenerator`** (alternative): works with **any OpenAI-compatible server** through its Chat Completions API (`GET {base URL}/models`, `POST {base URL}/chat/completions`).
  - The user picks a preset (OpenAI, Azure OpenAI, OpenRouter, Ollama, LM Studio) or enters any base URL. The key is sent as `Authorization: Bearer` or, for Azure, `api-key`.
  - **The API key is optional for local servers** (Ollama, LM Studio). **Plain `http` is only allowed for `localhost`, `127.0.0.1` and `*.local`**; everything else must use `https`. The ATS exception for this lives in `Config/NotesV-Info.plist` (`NSAllowsLocalNetworking`).
  - Ask for structured output with `response_format: json_schema` (`MeetingProtocol.jsonSchema`). If the server answers 400, fall back to `json_object`, then to plain text with the schema in the prompt, and extract the JSON from the answer.
  - **Default model: always the latest.** At runtime, read the server's models list, keep only text/chat models, and pick the newest by `created`. If the server doesn't report `created`, use its only model, or ask the user to choose one when there are several. Cache the result for a day per server. Never hard-code a model name as the default.
  - If the model lookup fails, use the last cached model and show a warning.
  - Settings lets the user override this with a specific model.
  - Tell the user in the UI where meeting data is sent: outside their Microsoft 365 tenant, or, for a local server, to this Mac only.

Provider selection:
- A **Settings** pane (SwiftUI `Settings` scene) lets the user:
  - choose the AI provider
  - choose the server (preset or base URL) and how the key is sent
  - enter or remove the API key
  - choose the model ("Latest" by default) and test the connection
  - pick the OneDrive storage folder
- Remember the provider, the model choice and the folder ID in `UserDefaults`. The rest of the app depends only on `ProtocolGenerator`, never on a concrete provider.

## Security and secrets

- **M365 tokens:** let MSAL handle token caching in the Keychain. Never log, print or store tokens yourself.
- **AI API keys:** store them **only in the macOS Keychain** (one per preset, via `KeychainService`). Never in `UserDefaults`, files, logs or source code, and never sync it to OneDrive.
- **App registration:** a multi-tenant Entra ID app. Customer admins may need to grant consent, so request the **smallest set of Graph permissions** that works: `User.Read`, `Calendars.Read` and `Files.ReadWrite`, plus whatever the Copilot API needs.
- Never commit client secrets, real customer tenant IDs or API keys. A public client desktop app shouldn't need a client secret.

## Architecture guidelines

- Keep the app split into clear layers:
  - `UI/`: SwiftUI views, the `NSTextView` editor wrapper, and Settings
  - `Domain/`: note, folder, meeting and protocol models, `MarkdownCodec`, and formatting logic
  - `Services/`: `AuthService` (MSAL), `CalendarService`, `StorageService` (OneDrive), `KeychainService`, `ProtocolGenerator` and its implementations
- Use protocols for services so they can be mocked in tests and previews.
- Use Swift Concurrency (`async/await`, `@MainActor` for UI state) and the Observation framework (`@Observable`).
- All user-facing strings go in a String Catalog (`Localizable.xcstrings`) with **Swedish and English**. No hard-coded UI text.

## Coding conventions

- Follow the Swift API Design Guidelines. Use SwiftLint/swift-format defaults if added.
- Prefer small views and computed properties over large view bodies.
- Write unit tests (Swift Testing) for the domain logic, Markdown round-trips, protocol formatting and service parsing, using mocked Graph and OpenAI responses (`MockTransport` replaces `HTTPTransport`). Tests must never call the real APIs.
- Code, comments and commit messages are in **English**.

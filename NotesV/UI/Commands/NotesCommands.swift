import AppKit
import SwiftUI

/// Sends an editor action to the text view that has keyboard focus.
@MainActor
enum EditorAction {
    static func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}

/// The menu bar commands, with the same keyboard shortcuts as Apple Notes.
struct NotesCommands: Commands {
    let store: NoteStore
    let protocolGeneration: ProtocolGenerationModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { store.createNote() }
                .keyboardShortcut("n")
            Button("New Folder") { store.isCreatingFolder = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button(store.selectedNote?.isPinned == true ? "Unpin Note" : "Pin Note") {
                if let noteID = store.selectedNoteID {
                    store.togglePin(noteID)
                }
            }
            .disabled(store.selectedNote == nil || store.selectedNote?.folderID == NoteFolder.recentlyDeletedName)
            Button("Generate Protocol…") {
                protocolGeneration.sourceNoteID = store.selectedNoteID
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(store.selectedNote?.document.hasContent != true)
        }

        CommandMenu("Format") {
            FormatMenuContent(includesShortcuts: true)
        }
    }
}

/// The Format menu items, used both in the menu bar and in the toolbar's Aa menu.
struct FormatMenuContent: View {
    let includesShortcuts: Bool

    var body: some View {
        item("Title", #selector(NotesTextView.formatTitle(_:)), "t", [.command, .shift])
        item("Heading", #selector(NotesTextView.formatHeading(_:)), "h", [.command, .shift])
        item("Subheading", #selector(NotesTextView.formatSubheading(_:)), "j", [.command, .shift])
        item("Body", #selector(NotesTextView.formatBody(_:)), "b", [.command, .shift])
        item("Monostyled", #selector(NotesTextView.formatMonostyled(_:)), "m", [.command, .shift])
        Divider()
        item("Bulleted List", #selector(NotesTextView.toggleBulletedList(_:)), "7", [.command, .shift])
        item("Dashed List", #selector(NotesTextView.toggleDashedList(_:)), "8", [.command, .shift])
        item("Numbered List", #selector(NotesTextView.toggleNumberedList(_:)), "9", [.command, .shift])
        Divider()
        item("Checklist", #selector(NotesTextView.toggleChecklist(_:)), "l", [.command, .shift])
        item("Mark as Checked", #selector(NotesTextView.toggleChecked(_:)), "u", [.command, .shift])
        Divider()
        item("Bold", #selector(NotesTextView.toggleNotesBold(_:)), "b", .command)
        item("Italic", #selector(NotesTextView.toggleNotesItalic(_:)), "i", .command)
        item("Underline", #selector(NotesTextView.toggleNotesUnderline(_:)), "u", .command)
        item("Strikethrough", #selector(NotesTextView.toggleNotesStrikethrough(_:)), "x", [.command, .shift])
        Divider()
        Menu("Table") {
            item("Insert Table", #selector(NotesTextView.insertNotesTable(_:)), "t", [.command, .option])
            Divider()
            item("Add Row", #selector(NotesTextView.addTableRow(_:)))
            item("Add Column", #selector(NotesTextView.addTableColumn(_:)))
            item("Delete Row", #selector(NotesTextView.deleteTableRow(_:)))
            item("Delete Column", #selector(NotesTextView.deleteTableColumn(_:)))
        }
        Divider()
        item("Increase Indent", #selector(NotesTextView.increaseListIndent(_:)), "]", .command)
        item("Decrease Indent", #selector(NotesTextView.decreaseListIndent(_:)), "[", .command)
    }

    @ViewBuilder
    private func item(
        _ title: LocalizedStringKey,
        _ action: Selector,
        _ key: KeyEquivalent? = nil,
        _ modifiers: EventModifiers = .command
    ) -> some View {
        let button = Button(title) { EditorAction.send(action) }
        if includesShortcuts, let key {
            button.keyboardShortcut(key, modifiers: modifiers)
        } else {
            button
        }
    }
}

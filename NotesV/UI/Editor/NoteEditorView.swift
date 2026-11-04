import AppKit
import SwiftUI

/// Shows a note in a `NotesTextView` and reports edits back as a `NoteDocument`.
struct NoteEditorView: NSViewRepresentable {
    let note: Note
    let focusOnLoad: Bool
    let onChange: (NoteDocument) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = NotesTextView.makeScrollableTextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        guard let textView = coordinator.textView else { return }

        let modified = note.modified.formatted(date: .long, time: .shortened)
        textView.headerText = note.sentAt.map { sentAt in
            let sent = sentAt.formatted(date: .abbreviated, time: .shortened)
            return String(localized: "\(modified) · Sent \(sent)")
        } ?? modified

        // Reload for another note, or when the same note was edited in another window.
        // This view's own edits are already in `lastDocument`, so typing never reloads.
        guard coordinator.noteID != note.id || coordinator.lastDocument != note.document else { return }
        let isNewNote = coordinator.noteID != note.id
        coordinator.noteID = note.id
        coordinator.lastDocument = note.document
        textView.load(note.document)
        guard isNewNote else { return }
        if focusOnLoad {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NotesTextView?
        var noteID: UUID?
        var lastDocument: NoteDocument?
        var onChange: (NoteDocument) -> Void = { _ in }

        func textDidChange(_ notification: Notification) {
            guard let textStorage = textView?.textStorage else { return }
            let document = AttributedStringConverter.document(from: textStorage)
            lastDocument = document
            onChange(document)
        }
    }
}

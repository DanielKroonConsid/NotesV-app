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

        textView.headerText = note.modified.formatted(date: .long, time: .shortened)

        // Only reload when another note is shown. Edits flow from the text view to the store, not back.
        guard coordinator.noteID != note.id else { return }
        coordinator.noteID = note.id
        textView.load(note.document)
        if focusOnLoad {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NotesTextView?
        var noteID: UUID?
        var onChange: (NoteDocument) -> Void = { _ in }

        func textDidChange(_ notification: Notification) {
            guard let textStorage = textView?.textStorage else { return }
            onChange(AttributedStringConverter.document(from: textStorage))
        }
    }
}

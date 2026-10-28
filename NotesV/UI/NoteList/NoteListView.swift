import SwiftUI

/// The note list in the second column, grouped like in Notes.
struct NoteListView: View {
    @Environment(NoteStore.self) private var store

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedNoteID) {
            ForEach(store.noteSections) { section in
                Section {
                    ForEach(section.notes) { note in
                        NoteRowView(note: note)
                            .tag(note.id)
                            .contextMenu { contextMenu(for: note) }
                    }
                } header: {
                    SectionHeader(id: section.id)
                }
            }
        }
        .overlay {
            if store.isLoaded, store.visibleNotes.isEmpty {
                if store.isSearching {
                    ContentUnavailableView.search(text: store.searchText)
                } else {
                    ContentUnavailableView("No Notes", systemImage: "note.text")
                }
            }
        }
        .onDeleteCommand {
            if let noteID = store.selectedNoteID {
                store.deleteNote(noteID)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    if let noteID = store.selectedNoteID {
                        store.deleteNote(noteID)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help(Text("Delete"))
                .disabled(store.selectedNoteID == nil)

                Button {
                    store.createNote()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .help(Text("New Note"))
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for note: Note) -> some View {
        if note.folderID != NoteFolder.recentlyDeletedName {
            Button(note.isPinned ? "Unpin Note" : "Pin Note") {
                store.togglePin(note.id)
            }
        }
        Menu("Move To") {
            ForEach(store.folders.filter { $0.kind == .regular && $0.id != note.folderID }) { folder in
                Button(folder.name == NoteFolder.defaultName ? String(localized: "Notes") : folder.name) {
                    store.moveNote(note.id, to: folder.id)
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            store.deleteNote(note.id)
        }
    }
}

private struct SectionHeader: View {
    let id: NoteStore.NoteSection.ID

    var body: some View {
        switch id {
        case .pinned:
            Text("Pinned")
        case .date(.today):
            Text("Today")
        case .date(.yesterday):
            Text("Yesterday")
        case .date(.previous7Days):
            Text("Previous 7 Days")
        case .date(.previous30Days):
            Text("Previous 30 Days")
        case .date(.month(let year, let month)):
            Text(verbatim: monthTitle(year: year, month: month))
        }
    }

    private func monthTitle(year: Int, month: Int) -> String {
        let calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(year: year, month: month)) else { return "" }
        if year == calendar.component(.year, from: .now) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if note.meeting != nil {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                }
                title
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(verbatim: dateText)
                preview
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.callout)
        }
        .padding(.vertical, 4)
    }

    private var title: Text {
        let title = note.document.title
        return title.isEmpty ? Text("New Note") : Text(verbatim: title)
    }

    private var preview: Text {
        let preview = note.document.previewText
        return preview.isEmpty ? Text("No additional text") : Text(verbatim: preview)
    }

    private var dateText: String {
        Calendar.current.isDateInToday(note.modified)
            ? note.modified.formatted(date: .omitted, time: .shortened)
            : note.modified.formatted(date: .numeric, time: .omitted)
    }
}

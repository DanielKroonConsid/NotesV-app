import SwiftUI

/// The overview of the tasks in all protocols. A task shows its protocol in the editor column.
struct ActionItemListView: View {
    @Environment(NoteStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var filter = ActionItemOverview.Filter.mine
    @State private var sort = ActionItemOverview.Sort.dueDate
    @State private var showsDone = false
    @State private var selection: ActionItemRow.ID?
    @State private var isReviewing = false
    @State private var editedRow: ActionItemRow?

    private var sections: [ActionItemOverview.Section] {
        ActionItemOverview.sections(
            of: store.actionItemRows, filter: filter, sort: sort, showsDone: showsDone, searchText: store.searchText
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            List(selection: $selection) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            ActionItemRowView(row: row)
                                .tag(row.id)
                                .contextMenu { contextMenu(for: row) }
                        }
                    } header: {
                        ActionItemSectionHeader(section: section)
                    }
                }
            }
            .overlay {
                if sections.isEmpty {
                    if store.isSearching {
                        ContentUnavailableView.search(text: store.searchText)
                    } else {
                        ContentUnavailableView("No Tasks", systemImage: "checklist")
                    }
                }
            }
        }
        .onChange(of: selection) { _, id in
            store.selectedNoteID = id?.noteID
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        Text("Due Date").tag(ActionItemOverview.Sort.dueDate)
                        Text("Meeting").tag(ActionItemOverview.Sort.meeting)
                        Text("Owner").tag(ActionItemOverview.Sort.owner)
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Show Completed", isOn: $showsDone)
                } label: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                }
                .help(Text("Sort By"))
            }
        }
        .sheet(isPresented: $isReviewing) {
            ActionItemReviewSheet()
        }
        .sheet(item: $editedRow) { row in
            ActionItemEditSheet(row: row, people: store.notes[row.noteID]?.actionItemPeople ?? [])
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            if store.newActionItemCount > 0 {
                Button {
                    isReviewing = true
                } label: {
                    Label("\(store.newActionItemCount) new tasks", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Picker("Show", selection: $filter) {
                Text("Mine").tag(ActionItemOverview.Filter.mine)
                Text("Others").tag(ActionItemOverview.Filter.others)
                Text("All").tag(ActionItemOverview.Filter.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(10)
    }

    @ViewBuilder
    private func contextMenu(for row: ActionItemRow) -> some View {
        Button("Edit…") {
            editedRow = row
        }
        Button("Open Protocol in Its Own Window") {
            openWindow(id: ProtocolWindowView.windowID, value: row.noteID)
        }
        Divider()
        Button("Remove from List", role: .destructive) {
            store.removeActionItem(row.id)
        }
    }
}

private struct ActionItemSectionHeader: View {
    let section: ActionItemOverview.Section

    var body: some View {
        switch section.id {
        case .overdue:
            Text("Overdue").foregroundStyle(.red)
        case .today:
            Text("Today")
        case .thisWeek:
            Text("This Week")
        case .later:
            Text("Later")
        case .noDate:
            Text("No Date")
        case .done:
            Text("Completed")
        case .meeting:
            Text(verbatim: section.title ?? "")
        case .me:
            Text("Me")
        case .owner(let name):
            Text(verbatim: name)
        case .noOwner:
            Text("No owner").foregroundStyle(.orange)
        }
    }
}

private struct ActionItemRowView: View {
    let row: ActionItemRow

    @Environment(NoteStore.self) private var store

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("Completed", isOn: Binding(
                get: { row.isDone },
                set: { store.setActionItem(row.id, done: $0) }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.item.task)
                    .fontWeight(.semibold)
                    .strikethrough(row.isDone)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    owner
                    if let dueDate = row.item.dueDate {
                        Text(verbatim: dueDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(row.isOverdue(on: Calendar.current.startOfDay(for: .now)) ? .red : .secondary)
                    }
                }
                .font(.callout)
                Label {
                    Text(verbatim: row.meetingTitle)
                } icon: {
                    Image(systemName: "doc.text")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var owner: some View {
        if row.item.isMine {
            Text("Me")
        } else if let name = row.item.owner {
            Text(verbatim: name).lineLimit(1)
        } else {
            Text("No owner").foregroundStyle(.orange)
        }
    }
}

/// Changes a task that is already in the list. The protocol's text stays as it is.
private struct ActionItemEditSheet: View {
    let row: ActionItemRow
    let people: [String]

    @Environment(NoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var item: ActionItem

    init(row: ActionItemRow, people: [String]) {
        self.row = row
        self.people = people
        _item = State(initialValue: row.item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Task")
                .font(.headline)
            ActionItemEditor(item: $item, people: people)
            Text("The text in the protocol doesn’t change.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.updateActionItem(row.id, to: item)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(item.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

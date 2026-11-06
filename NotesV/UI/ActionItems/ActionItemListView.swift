import SwiftUI

/// The overview of the tasks in all protocols. A task shows its protocol in the editor column.
struct ActionItemListView: View {
    @Environment(NoteStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var filter = ActionItemOverview.Filter.mine
    @State private var sort = ActionItemOverview.Sort.dueDate
    @AppStorage("tasks.showsCompleted") private var showsDone = true
    @State private var selection: ActionItemRow.ID?
    @State private var isReviewing = false
    @State private var editedRow: ActionItemRow?
    @State private var isCreating = false
    @State private var rowToRemove: ActionItemRow?

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
                        }
                    } header: {
                        ActionItemSectionHeader(section: section)
                    }
                }
            }
            // The primary action is what a double-click does.
            .contextMenu(forSelectionType: ActionItemRow.ID.self) { ids in
                if let row = row(in: ids) {
                    contextMenu(for: row)
                }
            } primaryAction: { ids in
                editedRow = row(in: ids)
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
            // A manual task has no protocol to show.
            store.selectedNoteID = id.flatMap { store.notes[$0.noteID]?.holdsManualTasks == true ? nil : $0.noteID }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isCreating = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .help(Text("New Task"))
            }
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
        .alert(
            "Remove this task from the list?",
            isPresented: Binding(get: { rowToRemove != nil }, set: { if !$0 { rowToRemove = nil } }),
            presenting: rowToRemove
        ) { row in
            Button("Cancel", role: .cancel) {}
            Button("OK", role: .destructive) { store.removeActionItem(row.id) }
        } message: { row in
            if row.isManual {
                Text("You can’t undo this action.")
            } else {
                Text("The checkbox stays in the protocol, but it won’t be suggested again.")
            }
        }
        .sheet(isPresented: $isCreating) {
            ActionItemFormSheet(title: "New Task", item: ActionItem(source: "", task: "", isMine: true), people: store.actionItemPeople) { item in
                var item = item
                item.source = item.task
                store.addManualActionItem(item)
            }
        }
        .sheet(item: $editedRow) { row in
            ActionItemFormSheet(
                title: "Edit Task",
                footnote: row.isManual ? nil : "The text in the protocol doesn’t change.",
                item: row.item,
                people: store.actionItemPeople
            ) { item in
                store.updateActionItem(row.id, to: item)
            }
        }
    }

    private func row(in ids: Set<ActionItemRow.ID>) -> ActionItemRow? {
        store.actionItemRows.first { ids.contains($0.id) }
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
        if !row.isManual {
            Button("Open Protocol in Its Own Window") {
                openWindow(id: ProtocolWindowView.windowID, value: row.noteID)
            }
        }
        Divider()
        Button("Remove from List", role: .destructive) {
            rowToRemove = row
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
            if let title = section.title, !title.isEmpty {
                Text(verbatim: title)
            } else {
                Text("Manual Tasks")
            }
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
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: row.item.task)
                        .fontWeight(.semibold)
                        .strikethrough(row.isDone)
                        .foregroundStyle(row.isDone ? .secondary : .primary)
                        .lineLimit(2)
                    if !row.item.subtasks.isEmpty {
                        Spacer(minLength: 4)
                        Text(verbatim: subtaskProgress)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    owner
                    if let dueDate = row.item.dueDate {
                        Text(verbatim: dueDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(row.isOverdue(on: Calendar.current.startOfDay(for: .now)) ? .red : .secondary)
                    }
                }
                .font(.callout)
                source
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let note = row.item.note {
                    Label {
                        Text(verbatim: note.prefix { !$0.isNewline }.description)
                    } icon: {
                        Image(systemName: "note.text")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                ForEach(Array(row.item.subtasks.enumerated()), id: \.element.id) { index, subtask in
                    Toggle(isOn: Binding(
                        get: { subtask.isDone },
                        set: { store.setSubtask(index, of: row.id, done: $0) }
                    )) {
                        Text(verbatim: subtask.title)
                            .strikethrough(subtask.isDone)
                            .foregroundStyle(subtask.isDone ? .secondary : .primary)
                            .lineLimit(2)
                    }
                    .font(.callout)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .help(Text(verbatim: row.item.note ?? ""))
    }

    private var subtaskProgress: String {
        "\(row.item.subtasks.filter(\.isDone).count)/\(row.item.subtasks.count)"
    }

    @ViewBuilder
    private var source: some View {
        if row.isManual {
            Label("Manual Task", systemImage: "pencil")
        } else {
            Label {
                Text(verbatim: row.meetingTitle)
            } icon: {
                Image(systemName: "doc.text")
            }
        }
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

/// Creates a task, or changes one that is already in the list.
private struct ActionItemFormSheet: View {
    let title: LocalizedStringKey
    var footnote: LocalizedStringKey?
    let people: [String]
    let onSave: (ActionItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var item: ActionItem

    init(
        title: LocalizedStringKey,
        footnote: LocalizedStringKey? = nil,
        item: ActionItem,
        people: [String],
        onSave: @escaping (ActionItem) -> Void
    ) {
        self.title = title
        self.footnote = footnote
        self.people = people
        self.onSave = onSave
        _item = State(initialValue: item)
    }

    private var trimmedTask: String {
        item.task.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            ActionItemEditor(item: $item, people: people)
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    item.task = trimmedTask
                    onSave(item)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedTask.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

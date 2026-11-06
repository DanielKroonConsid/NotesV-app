import SwiftUI

/// The fields of one task. Used when reviewing new tasks and when changing a task.
struct ActionItemEditor: View {
    @Binding var item: ActionItem
    let people: [String]
    /// The date as the protocol has it, when the app couldn't read it.
    var unreadDueText: String?

    @FocusState private var focusedSubtask: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Task", text: $item.task, prompt: Text("Task"), axis: .vertical)
            HStack {
                TextField("Owner", text: ownerText, prompt: Text("Owner"))
                Menu {
                    Button("Me") {
                        item.isMine = true
                        item.owner = nil
                    }
                    if !people.isEmpty {
                        Divider()
                    }
                    ForEach(people, id: \.self) { name in
                        Button(name) {
                            item.isMine = false
                            item.owner = name
                        }
                    }
                    Divider()
                    Button("No owner") {
                        item.isMine = false
                        item.owner = nil
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("Choose owner"))
                .accessibilityLabel(Text("Choose owner"))

                Toggle("Due date", isOn: hasDueDate)
                    .labelsHidden()
                    .help(Text("Due date"))
                if item.dueDate != nil {
                    DatePicker("Due date", selection: dueDate, displayedComponents: .date)
                        .datePickerStyle(.field)
                } else {
                    Text("Due date")
                        .foregroundStyle(.secondary)
                }
            }
            if let unreadDueText, item.dueDate == nil {
                Text("The protocol says: \(unreadDueText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            noteField
            subtasks
        }
        .labelsHidden()
    }

    /// A text editor, because Return in a multi-line text field would save the form.
    private var noteField: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Note")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: noteText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 56)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
                }
                .accessibilityLabel(Text("Note"))
        }
    }

    private var subtasks: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Subtasks")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(item.subtasks) { subtask in
                HStack {
                    Toggle("Completed", isOn: binding(for: subtask).isDone)
                    TextField("Subtask", text: binding(for: subtask).title, prompt: Text("Subtask"))
                        .focused($focusedSubtask, equals: subtask.id)
                    Button {
                        item.subtasks.removeAll { $0.id == subtask.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Remove Subtask"))
                    .accessibilityLabel(Text("Remove Subtask"))
                }
            }
            Button {
                let subtask = ActionItem.Subtask(title: "")
                item.subtasks.append(subtask)
                focusedSubtask = subtask.id
            } label: {
                Label("Add Subtask", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    /// Finds the subtask by id, because a binding by position can outlive a removed row and crash.
    private func binding(for subtask: ActionItem.Subtask) -> Binding<ActionItem.Subtask> {
        Binding(
            get: { item.subtasks.first { $0.id == subtask.id } ?? subtask },
            set: { newValue in
                guard let index = item.subtasks.firstIndex(where: { $0.id == subtask.id }) else { return }
                item.subtasks[index] = newValue
            }
        )
    }

    private var noteText: Binding<String> {
        Binding(
            get: { item.note ?? "" },
            set: { item.note = $0.isEmpty ? nil : $0 }
        )
    }

    private var ownerText: Binding<String> {
        Binding(
            get: { item.isMine ? String(localized: "Me") : item.owner ?? "" },
            set: { text in
                item.isMine = false
                item.owner = text.isEmpty ? nil : text
            }
        )
    }

    private var hasDueDate: Binding<Bool> {
        Binding(
            get: { item.dueDate != nil },
            set: { item.dueDate = $0 ? DueDateParser.calendar.startOfDay(for: .now) : nil }
        )
    }

    private var dueDate: Binding<Date> {
        Binding(
            get: { item.dueDate ?? .now },
            set: { item.dueDate = DueDateParser.calendar.startOfDay(for: $0) }
        )
    }
}

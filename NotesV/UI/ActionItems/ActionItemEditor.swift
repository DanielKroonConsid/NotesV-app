import SwiftUI

/// The fields of one task. Used when reviewing new tasks and when changing a task.
struct ActionItemEditor: View {
    @Binding var item: ActionItem
    let people: [String]
    /// The date as the protocol has it, when the app couldn't read it.
    var unreadDueText: String?

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
            .labelsHidden()
            if let unreadDueText, item.dueDate == nil {
                Text("The protocol says: \(unreadDueText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

import SwiftUI

/// Lets the user confirm who attended and match action items with owners before the protocol is created.
struct ProtocolReview: View {
    @Binding var minutes: MeetingProtocol
    let meeting: MeetingDetails
    let onCreate: () -> Void
    let onCancel: () -> Void

    /// Read once, so that a name being typed doesn't show up in the menus.
    @State private var candidates: [String] = []
    /// Read once, so that the rows stay in place when a box is ticked.
    @State private var people: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Protocol")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !people.isEmpty {
                        attendanceSection
                    }
                    if !minutes.actionItems.isEmpty {
                        ownersSection
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 420)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create Protocol", action: onCreate)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            candidates = minutes.ownerCandidates(for: meeting)
            people = minutes.attendanceCandidates(for: meeting)
        }
    }

    private var attendanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(
                Text("Attendance"),
                detail: Text("Tick the people who attended. Everyone else is listed as absent.")
            )
            ForEach(people, id: \.self) { name in
                Toggle(isOn: attended(name)) {
                    Text(verbatim: name)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var ownersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                Text("Match Owners"),
                detail: Text("Choose who is responsible for each action item. The due date is optional.")
            )
            ForEach(minutes.actionItems.indices, id: \.self) { index in
                ActionItemRow(item: $minutes.actionItems[index], candidates: candidates)
            }
        }
    }

    private func sectionHeader(_ title: Text, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title.fontWeight(.semibold)
            detail
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func attended(_ name: String) -> Binding<Bool> {
        Binding(
            get: { minutes.attendeesPresent.contains(name) },
            set: { minutes.setAttended($0, name: name) }
        )
    }
}

private struct ActionItemRow: View {
    @Binding var item: MeetingProtocol.ActionItem
    let candidates: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: item.task)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Owner", text: optionalText(\.owner), prompt: Text("Owner"))
                Menu {
                    ForEach(candidates, id: \.self) { name in
                        Button(name) { item.owner = name }
                    }
                    Divider()
                    Button("No owner") { item.owner = nil }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("Choose owner"))
                .accessibilityLabel(Text("Choose owner"))

                TextField("Due date", text: optionalText(\.dueDate), prompt: Text("Due date"))
                    .frame(width: 130)
            }
            .labelsHidden()
        }
    }

    private func optionalText(_ keyPath: WritableKeyPath<MeetingProtocol.ActionItem, String?>) -> Binding<String> {
        Binding(
            get: { item[keyPath: keyPath] ?? "" },
            set: { item[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}

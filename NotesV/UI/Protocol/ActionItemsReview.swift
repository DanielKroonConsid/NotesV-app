import SwiftUI

/// Lets the user match each action item with an owner before the protocol is created.
struct ActionItemsReview: View {
    @Binding var minutes: MeetingProtocol
    let meeting: MeetingDetails
    let onCreate: () -> Void
    let onCancel: () -> Void

    /// Read once, so that a name being typed doesn't show up in the menus.
    @State private var candidates: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Match Owners")
                .font(.headline)
            Text("Choose who is responsible for each action item. The due date is optional.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(minutes.actionItems.indices, id: \.self) { index in
                        ActionItemRow(item: $minutes.actionItems[index], candidates: candidates)
                    }
                }
                .padding(.vertical, 4)
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
        .onAppear { candidates = minutes.ownerCandidates(for: meeting) }
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

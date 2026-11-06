import SwiftUI

/// Lets the user complete new tasks before they are added to the list.
struct ActionItemReviewSheet: View {
    @Environment(NoteStore.self) private var store
    @Environment(ProfileSettings.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State private var proposals: [ActionItemProposal] = []
    @State private var didLoad = false

    private var includedCount: Int {
        proposals.reduce(0) { $0 + $1.drafts.filter(\.isIncluded).count }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach($proposals) { $proposal in
                    Section {
                        ForEach($proposal.drafts) { $draft in
                            row(draft: $draft, people: proposal.people)
                        }
                    } header: {
                        Text(verbatim: proposal.title)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text("Clear a box to decide later. Ignore keeps a task out of the list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(includedCount == 0)
            }
            .padding()
        }
        .frame(width: 600, height: 520)
        .navigationTitle(Text("New Tasks"))
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            proposals = store.actionItemProposals(myNames: profile.names)
        }
    }

    private func row(draft: Binding<ActionItemDraft>, people: [String]) -> some View {
        HStack(alignment: .top) {
            Toggle("Add", isOn: draft.isIncluded)
                .labelsHidden()
            ActionItemEditor(item: draft.item, people: people, unreadDueText: draft.wrappedValue.unreadDueText)
                .disabled(!draft.wrappedValue.isIncluded)
            Button {
                ignore(draft.wrappedValue)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(Text("Ignore"))
            .accessibilityLabel(Text("Ignore"))
        }
    }

    private func ignore(_ draft: ActionItemDraft) {
        store.ignoreActionItem(draft.item, in: draft.noteID)
        for index in proposals.indices {
            proposals[index].drafts.removeAll { $0.id == draft.id }
        }
        proposals.removeAll(where: \.drafts.isEmpty)
        if proposals.isEmpty {
            dismiss()
        }
    }

    private func add() {
        for proposal in proposals {
            store.addActionItems(proposal.drafts.filter(\.isIncluded).map(\.item), to: proposal.noteID)
        }
        dismiss()
    }
}

import SwiftUI
import SwiftData
import CoreModel

// Reusable category chooser. Caller persists via the onSelect callback (so it works for a
// single tx, a quick swipe, or bulk). Includes an "Uncategorized" option.
struct CategoryPickerView: View {
    let selectedId: UUID?
    let onSelect: (CoreModel.Category?) -> Void

    @Query(sort: [SortDescriptor(\CoreModel.Category.name)])
    private var categories: [CoreModel.Category]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [CoreModel.Category] {
        guard !search.isEmpty else { return categories }
        return categories.filter { $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Button { choose(nil) } label: {
                        row(name: "Uncategorized", color: nil, selected: selectedId == nil)
                    }
                    .tint(.primary)
                }
                ForEach(filtered) { cat in
                    Button { choose(cat) } label: {
                        row(name: cat.name, color: cat.color, selected: cat.id == selectedId)
                    }
                    .tint(.primary)
                }
            }
            .searchable(text: $search, prompt: "Category")
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(name: String, color: String?, selected: Bool) -> some View {
        HStack(spacing: 12) {
            ColorDot(hex: color)
            Text(name)
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func choose(_ category: CoreModel.Category?) {
        onSelect(category)
        dismiss()
    }
}

#if DEBUG
#Preview {
    CategoryPickerView(selectedId: nil) { _ in }
        .modelContainer(PreviewData.container)
}
#endif

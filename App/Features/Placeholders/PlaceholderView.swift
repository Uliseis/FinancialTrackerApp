import SwiftUI

struct PlaceholderView: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text("Coming in a later slice.")
            )
            .navigationTitle(title)
        }
    }
}

#if DEBUG
#Preview {
    PlaceholderView(title: "Transactions", systemImage: "list.bullet.rectangle")
}
#endif

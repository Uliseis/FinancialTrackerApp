import SwiftUI

// Shared alert for mutation failures so a thrown validation/save error never gets
// silently swallowed behind a dismiss(). Bind a `@State var saveError: String?`;
// setting it presents the alert. The Binding(get:set:) adapter is contained here
// (the standard optional→isPresented bridge), not repeated in view bodies.
extension View {
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Couldn’t Save",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {} message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

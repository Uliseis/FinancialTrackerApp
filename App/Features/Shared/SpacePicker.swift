import SwiftUI
import SwiftData
import CoreModel

// Shared current-space selector. Persists globally via @AppStorage so switching space in
// one tab reflects everywhere. Hidden when there is ≤1 space (parity with SpaceTabs).
struct SpacePicker: View {
    @Query(sort: [SortDescriptor(\AccountSpace.sortOrder),
                  SortDescriptor(\AccountSpace.createdAt)])
    private var spaces: [AccountSpace]

    @AppStorage(SpaceSelection.key) private var currentSpaceId = ""

    private var selected: AccountSpace? {
        SpaceScope.resolve(rawCurrentId: currentSpaceId, spaces: spaces).current
    }

    var body: some View {
        if spaces.count > 1 {
            Menu {
                ForEach(spaces) { space in
                    Button {
                        currentSpaceId = space.id.uuidString
                    } label: {
                        if space.id == selected?.id {
                            Label(space.name, systemImage: "checkmark")
                        } else {
                            Text(space.name)
                        }
                    }
                }
            } label: {
                Label(selected?.name ?? "Space", systemImage: "rectangle.stack")
            }
        }
    }
}

enum SpaceSelection {
    static let key = "currentSpaceId"
}

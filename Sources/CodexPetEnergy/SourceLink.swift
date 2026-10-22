import SwiftUI

/// A visible link affordance that follows the app's monochrome hierarchy on macOS.
struct SourceLink: View {
    let title: String
    let destination: URL

    init(_ title: String, destination: URL) {
        self.title = title
        self.destination = destination
    }

    var body: some View {
        Link(destination: destination) {
            Text(title).underline().foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

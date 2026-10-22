import AppKit
import SwiftUI

struct AppBrandIcon: View {
    private static let artwork: NSImage? = Bundle.main.url(forResource: "AppLogo", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        if let artwork = Self.artwork {
            Image(nsImage: artwork).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: "bolt.circle.fill").resizable().scaledToFit()
                .foregroundStyle(EnergyVisualStyle.computeAccent)
        }
    }
}

import SwiftUI

/// Lane colors. Blue is the mainline only; other lanes rotate through the rest.
enum GraphPalette {
    static let colors: [Color] = [.blue, .purple, .teal, .orange, .green, .pink, .brown]

    static func color(for index: Int) -> Color {
        index == 0 ? colors[0] : colors[1 + (index - 1) % (colors.count - 1)]
    }
}

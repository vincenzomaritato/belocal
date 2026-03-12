import SwiftUI

extension View {
    func accessibilityTapTarget(minSize: CGFloat = 44) -> some View {
        frame(minWidth: minSize, minHeight: minSize)
            .contentShape(Rectangle())
    }
}

import SwiftUI

struct ProfileToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle")
                .font(.title3.weight(.semibold))
        }
        .accessibilityLabel("Open profile")
        .accessibilityHint("Opens account settings and travel preferences")
    }
}

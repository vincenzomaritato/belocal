import SwiftUI

struct ProfileToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle")
                .font(.title3.weight(.semibold))
        }
        .accessibilityLabel(L10n.tr("Open profile"))
        .accessibilityHint(L10n.tr("Opens account settings and travel preferences"))
    }
}

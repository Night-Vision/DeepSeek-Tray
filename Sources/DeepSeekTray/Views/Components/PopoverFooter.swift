import SwiftUI

struct PopoverFooter: View {
    let left: String
    let right: String

    var body: some View {
        HStack {
            Text(left)
            Spacer()
            Text(right)
        }
        .font(.system(size: 11))
        .foregroundColor(.dsTextTertiary)
        .padding(.top, 12)
        .overlay(Divider().background(Color.dsBorder), alignment: .top)
    }
}

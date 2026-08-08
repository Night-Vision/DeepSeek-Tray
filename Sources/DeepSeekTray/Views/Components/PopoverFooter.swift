import SwiftUI

struct PopoverFooter: View {
    let left: String
    let right: String

    var body: some View {
        VStack(spacing: 8) {
            Divider()
                .background(Color.dsBorder)
            HStack {
                Text(left)
                Spacer()
                Text(right)
            }
            .font(.system(size: 11))
            .foregroundColor(.dsTextTertiary)
        }
        .padding(.top, 10)
    }
}

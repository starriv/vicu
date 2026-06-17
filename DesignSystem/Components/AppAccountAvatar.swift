import SwiftUI

struct AppAccountAvatar: View {
    let size: CGFloat
    let iconSize: CGFloat

    init(size: CGFloat, iconSize: CGFloat) {
        self.size = size
        self.iconSize = iconSize
    }

    var body: some View {
        Image(AppIcon.Tab.home)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(AppTheme.ColorToken.brand)
            .frame(width: iconSize, height: iconSize)
            .clipShape(Circle())
            .frame(width: size, height: size)
    }
}

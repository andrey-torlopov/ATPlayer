import Foundation
import OSLog
import SwiftUI
import UIKit

/// Resolves the loose PNG in the package resource bundle explicitly, without
/// relying on SwiftUI's image-name lookup. The decoded image is reused by every sheet.
@MainActor
enum DeveloperAvatarResource {
    static let resourceURL = Bundle.module.url(forResource: "avatar", withExtension: "png")

    static let image: UIImage? = {
        guard let resourceURL else {
            logger.error("Bundled developer avatar resource is missing.")
            return nil
        }
        guard let image = UIImage(contentsOfFile: resourceURL.path) else {
            logger.error("Bundled developer avatar resource could not be decoded.")
            return nil
        }
        return image
    }()

    private static let logger = Logger(subsystem: "ATPlayer.PlayerFeature", category: "DeveloperAvatar")
}

struct DeveloperAvatarV1: View {
    @Environment(\.playerThemeV1) private var theme

    var body: some View {
        Group {
            if let image = DeveloperAvatarResource.image {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(theme.surface)
                    Image(systemName: "person.fill")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .frame(width: 96, height: 96, alignment: .top)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(theme.border.opacity(0.6), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

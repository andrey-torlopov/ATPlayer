import AppLocalization
import SwiftUI
import UIKit

enum DeveloperExternalLink: String, CaseIterable, Identifiable {
    case boosty
    case repository

    var id: String { rawValue }

    var address: String {
        switch self {
        case .boosty: return "https://boosty.to/andreytorlopov"
        case .repository: return "https://github.com/andrey-torlopov/ATPlayer"
        }
    }

    var url: URL? { URL(string: address) }
}

@MainActor
final class DeveloperLinkAction: ObservableObject {
    @Published private(set) var pendingLink: DeveloperExternalLink?
    @Published var failedLink: DeveloperExternalLink?

    func open(_ link: DeveloperExternalLink,
              using opener: (URL, @escaping @MainActor (Bool) -> Void) -> Void) {
        guard pendingLink == nil else { return }
        guard let url = link.url else {
            failedLink = link
            return
        }
        failedLink = nil
        pendingLink = link
        opener(url) { [weak self] accepted in
            self?.pendingLink = nil
            self?.failedLink = accepted ? nil : link
        }
    }

    func copy(_ link: DeveloperExternalLink, using copyText: (String) -> Void) {
        copyText(link.address)
        failedLink = nil
    }
}

struct AboutDeveloperSectionV1: View {
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.playerThemeV1) private var theme
    @StateObject private var linkAction = DeveloperLinkAction()

    var body: some View {
        let _ = locale
        VStack(spacing: 24) {
            developer
            VStack(spacing: 12) {
                externalLink(.boosty, symbol: "heart", title: L10n.text("Мой Boosty"),
                             subtitle: "boosty.to/andreytorlopov")
                externalLink(.repository, symbol: "chevron.left.forwardslash.chevron.right",
                             title: L10n.text("Исходный код на GitHub"),
                             subtitle: "andrey-torlopov / ATPlayer")
            }
            applicationDescription
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .softPanelV1()
        .accessibilityIdentifier("settings-about-author")
        .alert(L10n.text("Не удалось открыть ссылку"), isPresented: Binding(
            get: { linkAction.failedLink != nil },
            set: { if !$0 { linkAction.failedLink = nil } }
        ), presenting: linkAction.failedLink) { link in
            Button(L10n.text("Повторить")) { open(link) }
            Button(L10n.text("Скопировать ссылку")) {
                linkAction.copy(link) { UIPasteboard.general.string = $0 }
            }
            Button(L10n.text("Отмена"), role: .cancel) { linkAction.failedLink = nil }
        } message: { link in
            Text(link.address)
        }
    }

    private var developer: some View {
        VStack(spacing: 12) {
            DeveloperAvatarV1()

            VStack(spacing: 5) {
                Text(L10n.text("Андрей Торлопов"))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(L10n.text("Разработчик ATPlayer"))
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var applicationDescription: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("Только ваша музыка"))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(theme.textPrimary)

            VStack(alignment: .leading, spacing: 14) {
                fact(L10n.text("Без оплаты"), symbol: "gift")
                fact(L10n.text("Без рекламы и аналитики"), symbol: "hand.raised")
                fact(L10n.text("Открытый исходный код"), symbol: "curlybraces")
                fact(L10n.text("Никаких сетевых запросов"), symbol: "globe")
            }

            Text(L10n.text("Интернет может понадобиться только если через сеть пытаетесь добавить трек и его надо в памяти закешировать."))
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fact(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(theme.accent)
                .frame(width: 22)
        }
    }

    private func externalLink(_ link: DeveloperExternalLink, symbol: String,
                              title: String, subtitle: String) -> some View {
        Button { open(link) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.accent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .softPanelV1(cornerRadius: 20)
        .disabled(linkAction.pendingLink != nil)
        .accessibilityLabel(title)
        .accessibilityHint(L10n.text("Открыть внешнюю ссылку"))
        .accessibilityIdentifier("about-link-\(link.rawValue)")
    }

    private func open(_ link: DeveloperExternalLink) {
        linkAction.open(link) { url, completion in
            openURL(url) { accepted in
                Task { @MainActor in completion(accepted) }
            }
        }
    }

}

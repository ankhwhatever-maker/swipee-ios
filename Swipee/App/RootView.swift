import SwiftUI
import UIKit

struct RootView: View {
    @State private var selectedTab: AppTab = .organize

    private enum AppTab: Hashable {
        case organize
        case duplicates
        case settings
    }

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.selectionIndicatorImage = Self.selectionIndicatorImage()
        appearance.selectionIndicatorTintColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.16)
                : UIColor.black.withAlphaComponent(0.08)
        }

        let itemAppearances = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ]
        for itemAppearance in itemAppearances {
            itemAppearance.normal.iconColor = .secondaryLabel
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
            itemAppearance.selected.iconColor = .label
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.label]
        }

        let tabBarAppearance = UITabBar.appearance()
        tabBarAppearance.standardAppearance = appearance
        tabBarAppearance.scrollEdgeAppearance = appearance
        tabBarAppearance.tintColor = .label
        tabBarAppearance.unselectedItemTintColor = .secondaryLabel
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { OrganizeView() }
                .toolbarBackground(Color(red: 0.043, green: 0.043, blue: 0.051), for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.dark, for: .tabBar)
                .tabItem {
                    Label("整理", systemImage: "rectangle.stack")
                        .symbolVariant(selectedTab == .organize ? .fill : .none)
                }
                .tag(AppTab.organize)

            NavigationStack { DuplicatesView() }
                .toolbarBackground(Color.swipeeSurface, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.light, for: .tabBar)
                .tabItem {
                    Label("重複", systemImage: "square.on.square")
                        .symbolVariant(selectedTab == .duplicates ? .fill : .none)
                }
                .tag(AppTab.duplicates)

            NavigationStack { SettingsView() }
                .toolbarBackground(Color.swipeeSurface, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.light, for: .tabBar)
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                        .symbolVariant(selectedTab == .settings ? .fill : .none)
                }
                .tag(AppTab.settings)
        }
    }

    private static func selectionIndicatorImage() -> UIImage {
        let size = CGSize(width: 92, height: 46)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2).fill()
        }
        .withRenderingMode(.alwaysTemplate)
    }
}

extension Color {
    static let swipeeBackground = Color(uiColor: .systemGroupedBackground)
    static let swipeeSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let swipeeElevatedSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let swipeeBorder = Color("SwipeeBorder")
    static let swipeeDelete = Color("SwipeeDelete")
    static let swipeeDestructive = Color(uiColor: .systemRed)
    static let swipeeFavorite = Color("SwipeeFavorite")
    static let swipeeKeep = Color("SwipeeKeep")
    static let swipeePhotoOverlay = Color("SwipeePhotoOverlay")
}

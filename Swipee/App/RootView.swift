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
        appearance.backgroundColor = UIColor(named: "SwipeeBackground") ?? .systemBackground
        appearance.stackedItemPositioning = .fill
        appearance.stackedItemSpacing = 0

        let itemAppearances = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ]
        for itemAppearance in itemAppearances {
            itemAppearance.normal.iconColor = .label
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.label]
            itemAppearance.selected.iconColor = .label
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.label]
        }

        let tabBarAppearance = UITabBar.appearance()
        tabBarAppearance.itemPositioning = .fill
        tabBarAppearance.itemSpacing = 0
        tabBarAppearance.standardAppearance = appearance
        tabBarAppearance.scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { OrganizeView() }
                .tabItem {
                    Label(
                        "整理",
                        systemImage: selectedTab == .organize ? "rectangle.stack.fill" : "rectangle.stack"
                    )
                }
                .tag(AppTab.organize)

            NavigationStack { DuplicatesView() }
                .tabItem {
                    Label(
                        "重複",
                        systemImage: selectedTab == .duplicates ? "square.on.square.fill" : "square.on.square"
                    )
                }
                .tag(AppTab.duplicates)

            NavigationStack { SettingsView() }
                .tabItem {
                    Label(
                        "設定",
                        systemImage: selectedTab == .settings ? "gearshape.fill" : "gearshape"
                    )
                }
                .tag(AppTab.settings)
        }
        .toolbarBackground(Color.swipeeBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

extension Color {
    static let swipeeBackground = Color("SwipeeBackground")
    static let swipeeSurface = Color("SwipeeSurface")
    static let swipeeElevatedSurface = Color("SwipeeElevatedSurface")
    static let swipeeBorder = Color("SwipeeBorder")
    static let swipeeDelete = Color("SwipeeDelete")
    static let swipeeFavorite = Color("SwipeeFavorite")
    static let swipeeKeep = Color("SwipeeKeep")
    static let swipeePhotoOverlay = Color("SwipeePhotoOverlay")
}

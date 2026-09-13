import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var duplicateAnalysis: DuplicateAnalysisService
    @EnvironmentObject private var pendingDeletions: PendingDeletionStore
    @EnvironmentObject private var photoLibrary: PhotoLibraryService

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
                        .environment(
                            \.symbolVariants,
                            selectedTab == .organize ? .fill : .none
                        )
                }
                .tag(AppTab.organize)

            NavigationStack { DuplicatesView() }
                .toolbarBackground(Color.swipeeSurface, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.light, for: .tabBar)
                .tabItem {
                    Label("重複", systemImage: "square.on.square")
                        .environment(
                            \.symbolVariants,
                            selectedTab == .duplicates ? .fill : .none
                        )
                }
                .tag(AppTab.duplicates)

            NavigationStack { SettingsView() }
                .toolbarBackground(Color.swipeeSurface, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.light, for: .tabBar)
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                        .environment(
                            \.symbolVariants,
                            selectedTab == .settings ? .fill : .none
                        )
                }
                .tag(AppTab.settings)
        }
        .task(id: automaticDuplicateAnalysisTrigger) {
            guard scenePhase == .active else { return }
            photoLibrary.refreshAuthorizationStatus()
            guard photoLibrary.canReadLibrary else { return }

            // A previous foreground task may still be winding down after cancellation.
            while duplicateAnalysis.isAnalyzing {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await duplicateAnalysis.analyzeAutomaticallyIfNeeded(
                library: photoLibrary,
                pendingDeletions: pendingDeletions
            )
        }
    }

    private var automaticDuplicateAnalysisTrigger: String {
        "\(scenePhase)-\(photoLibrary.authorizationStatus.rawValue)"
    }
}

extension Color {
    static let swipeeBackground = Color(uiColor: .systemGroupedBackground)
    static let swipeeSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let swipeeElevatedSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let swipeeBorder = Color("SwipeeBorder")
    static let swipeeDelete = Color("SwipeeDelete")
    static let swipeeKeep = Color("SwipeeKeep")
    static let swipeePhotoOverlay = Color("SwipeePhotoOverlay")
}

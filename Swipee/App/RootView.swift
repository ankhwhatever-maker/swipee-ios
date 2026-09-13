import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var duplicateAnalysis: DuplicateAnalysisService
    @EnvironmentObject private var pendingDeletions: PendingDeletionStore
    @EnvironmentObject private var photoLibrary: PhotoLibraryService
    @EnvironmentObject private var settings: CandidateSettingsStore
    @EnvironmentObject private var history: ReviewHistoryStore
    @EnvironmentObject private var reviewSession: ReviewSessionStore

    @State private var selectedTab: AppTab = .organize
    @State private var isShowingLaunchBrand = true

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
        ZStack {
            if isShowingLaunchBrand {
                launchBrandView
                    .transition(.opacity)
            } else {
                mainTabs
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isShowingLaunchBrand)
        .preferredColorScheme(isShowingLaunchBrand ? .light : nil)
        .task {
            await prepareInitialScreen()
        }
        .task(id: automaticDuplicateAnalysisTrigger) {
            guard scenePhase == .active, !isShowingLaunchBrand else { return }
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

    private var mainTabs: some View {
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
                .tabItem {
                    Label("重複", systemImage: "square.on.square")
                        .environment(
                            \.symbolVariants,
                            selectedTab == .duplicates ? .fill : .none
                        )
                }
                .tag(AppTab.duplicates)

            NavigationStack { SettingsView() }
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                        .environment(
                            \.symbolVariants,
                            selectedTab == .settings ? .fill : .none
                        )
                }
                .tag(AppTab.settings)
        }
        .toolbarBackground(Color(uiColor: .systemBackground), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private var launchBrandView: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
        }
    }

    private func prepareInitialScreen() async {
        let startedAt = Date()
        let minimumDisplayDuration: TimeInterval = 0.6
        let preparationDeadline = startedAt.addingTimeInterval(1.5)

        photoLibrary.refreshAuthorizationStatus()
        if photoLibrary.canReadLibrary {
            reviewSession.importPendingRecords(
                pendingDeletions.records.filter { !$0.sourceConditionKey.hasPrefix("duplicates|") }
            )

            if !reviewSession.isComplete {
                let selectedSettings = settings.value
                Task {
                    await photoLibrary.reloadIfNeeded(
                        settings: selectedSettings,
                        history: history,
                        pendingDeletions: pendingDeletions
                    )
                }

                while Date() < preparationDeadline,
                      !photoLibrary.hasLoadedCandidates(
                        for: selectedSettings,
                        pendingDeletionRevision: pendingDeletions.revision
                      ) {
                    do {
                        try await Task.sleep(for: .milliseconds(50))
                    } catch {
                        return
                    }
                }
            }
        }

        let remaining = minimumDisplayDuration - Date().timeIntervalSince(startedAt)
        if remaining > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            } catch {
                return
            }
        }
        isShowingLaunchBrand = false
    }

    private var automaticDuplicateAnalysisTrigger: String {
        "\(scenePhase)-\(photoLibrary.authorizationStatus.rawValue)-\(isShowingLaunchBrand)"
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
